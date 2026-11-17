import { DestroyRef, Injectable, inject, signal, effect, untracked } from '@angular/core';
import { CattleApiService } from './cattle-api.service';
import { AuthService, SessionScope, SessionState, TenantService } from 'core-auth';
import { OfflineStoreService } from './offline-store.service';
import { LoggerService } from './logger.service';
import { OfflineWipeEventsService } from './offline-wipe-events.service';
import { isNetworkFailure } from '@shared/utils/network-failure.util';
import { findFinancialLookingColumns, sanitizeLivestockForOffline, snapshotMatchesTenant } from '@shared/utils/offline-livestock.util';

const OFFLINE_NO_SNAPSHOT_MESSAGE = 'Sin conexión y sin datos guardados del inventario en este dispositivo.';
const NO_SESSION_MESSAGE = 'No hay una sesión válida para cargar el inventario de ganado.';

@Injectable({
  providedIn: 'root'
})
export class CattleDataService {
  private cattleApi = inject(CattleApiService);
  private tenantService = inject(TenantService);
  private auth = inject(AuthService);
  private offlineStore = inject(OfflineStoreService);
  private logger = inject(LoggerService);
  private wipeEvents = inject(OfflineWipeEventsService);

  // States reactivos globales del dominio ganadero
  public cattleList = signal<any[]>([]);
  public isLoading = signal<boolean>(false);

  // Último error de carga, para que un consumidor (ej. MainDashboardComponent) pueda mostrar
  // un estado de error explícito en vez de una tabla vacía indistinguible de "tenant sin hato".
  public loadError = signal<string | null>(null);

  // Se vuelve true tras el primer `.set()` exitoso y vuelve a false en cada reset por logout o cambio
  // de tenant (#1111): así el estado de error de "nunca cargamos el hato" nunca se aplica a un hato
  // anterior, y "0 animales reales" sigue distinguiéndose de "nunca llegamos a cargar datos reales".
  public hasLoadedOnce = signal<boolean>(false);

  // Offline read-through (#1087, phase 1b-iii-a): true while `cattleList` holds a cached snapshot
  // instead of live data; `cacheSavedAt` is that snapshot's ISO timestamp. Reset on a live load.
  public servedFromCache = signal<boolean>(false);
  public cacheSavedAt = signal<string | null>(null);

  // Guard de concurrencia "latest-wins": cada llamada obtiene un número de secuencia propio.
  // Si para cuando la respuesta llega ya se disparó una llamada más reciente (cambio de tenant,
  // un refresh manual/automático, etc.), la respuesta vieja se descarta sin tocar ningún signal
  // — nunca "gana" una respuesta tardía sobre una más reciente, sin importar el orden de llegada.
  private requestSeq = 0;
  // Last logged set of financial-looking column names (per instance), to avoid logging on every refresh.
  private lastFlaggedKey: string | null = null;
  // Conteo de llamadas en vuelo — permite que `isLoading` se apague solo cuando la ÚLTIMA
  // llamada pendiente termina, evitando que una llamada vieja apague el spinner mientras una
  // más nueva (ej. un segundo cambio de tenant disparado antes de que el primero resuelva)
  // todavía está en curso.
  private pendingRequests = 0;

  // Incrementa en cada emisión de activeTenantChanges$ (#1111). Es la ÚNICA señal que dispara la
  // recarga: al ser un contador, un cambio al mismo id (re-login, renombre de empresa) también
  // recarga, y varios cambios en el mismo tick se colapsan en una sola ejecución del effect.
  private tenantEpoch = signal<number>(0);

  constructor() {
    // Reset síncrono (#1111). Corre dentro de la misma llamada que cambió la sesión o el tenant, antes
    // de cualquier render. Solo resetea: la recarga la hace el effect de abajo, una sola vez.
    const subscriptions = [
      this.auth.sessionEvents$.subscribe(event => {
        if (event.type === 'logout') this.resetState();
      }),
      this.tenantService.activeTenantChanges$.subscribe(tenantId => {
        this.resetState();
        if (tenantId) this.tenantEpoch.update(n => n + 1);
      }),
      // The offline copy was wiped on expiry (#1087, 1b-iii-c): drop what is held in memory too.
      this.wipeEvents.wiped$.subscribe(() => this.resetState()),
    ];
    inject(DestroyRef).onDestroy(() => subscriptions.forEach(subscription => subscription.unsubscribe()));

    // Orquestador del ciclo de vida de los datos basado en el contexto de la empresa.
    // Deliberadamente SIN guard de "ya hay una carga en curso": un cambio de tenant siempre
    // debe disparar una carga nueva — el guard de secuencia dentro de loadCattleData() es lo
    // que garantiza que la respuesta más reciente sea la que gane, nunca un "skip if busy" aquí.
    effect(() => {
      this.tenantEpoch(); // dependencia deliberada: cada emisión de tenant
      const tenantId = this.tenantService.activeTenantId();
      if (tenantId) {
        // untracked: loadCattleData() reads session scope/state (-> TenantService.availableTenants())
        // synchronously; those reads must not become dependencies of this effect.
        untracked(() => this.loadCattleData());
      }
    }, { allowSignalWrites: true });
  }

  /**
   * Clears the herd and every flag, and invalidates requests in flight (#1111). Called synchronously on
   * logout and on every tenant emission. It never loads: the effect in the constructor does that.
   * Bumping `requestSeq` makes any response that is still pending for the previous session or tenant
   * stale, even when the scope would match again (same user, same tenant, after a logout in between).
   */
  private resetState(): void {
    this.requestSeq++;
    this.cattleList.set([]);
    this.loadError.set(null);
    this.hasLoadedOnce.set(false);
    this.servedFromCache.set(false);
    this.cacheSavedAt.set(null);
    this.isLoading.set(false);
  }

  /**
   * Ejecuta la petición HTTP hacia la capa Meta-CRUD a través de n8n
   * utilizando el contexto del Tenant activo actual.
   */
  public async loadCattleData(): Promise<void> {
    const seq = ++this.requestSeq;
    this.pendingRequests++;
    this.isLoading.set(true);
    // Scope and session state are captured BEFORE any request: a tenant switch while the request
    // is in flight must never store (or show) this response under the new tenant.
    const scope = this.captureScope();
    const state = this.captureState();
    try {
      if (!scope) {
        // Fail closed (#1111): without a verified session scope nothing is requested, cached or shown.
        this.cattleList.set([]);
        this.servedFromCache.set(false);
        this.cacheSavedAt.set(null);
        this.loadError.set(NO_SESSION_MESSAGE);
        return;
      }
      if (state === 'grace') {
        // No HTTP at all in grace: the auth interceptor would call logout() on the expired token.
        await this.serveFromCache(seq, scope, OFFLINE_NO_SNAPSHOT_MESSAGE, true);
        return;
      }

      const data = await this.cattleApi.getAllLivestock();
      if (seq !== this.requestSeq) return; // una llamada más reciente ya está en curso/resuelta — descartar
      if (scope && !this.isCurrentScope(scope)) return; // tenant/user changed in flight — nothing stale

      this.cattleList.set(data || []);
      this.hasLoadedOnce.set(true);
      this.loadError.set(null);
      this.servedFromCache.set(false);
      this.cacheSavedAt.set(null);
      if (state === 'valid' && scope) this.storeSnapshot(data || [], scope);
    } catch (error: any) {
      if (seq !== this.requestSeq) return; // idem — no pisar un estado más nuevo con un error viejo

      // Only a genuine network failure on a valid session may fall back to the cache. Gateway
      // error:true, HTTP >= 400 and expired sessions never substitute cached data.
      if (state === 'valid' && isNetworkFailure(error)) {
        const served = await this.serveFromCache(seq, scope, null, false);
        if (served || seq !== this.requestSeq) return;
      }

      console.error('Error crítico en el Data Pipeline de CattleDataService:', error);
      this.loadError.set(error?.message || 'No se pudo cargar el inventario de ganado.');
      // MetaCRUD Silent Error Shield: cattleList() NO se vacía — se conserva el último dato bueno.
    } finally {
      this.pendingRequests--;
      if (this.pendingRequests === 0) this.isLoading.set(false);
    }
  }

  /**
   * Serves the cached snapshot if this call is still the latest and the scope is unchanged.
   * Returns true when a snapshot was applied. With `failMessage`, a missing snapshot sets that
   * error and empties the list (grace has no live data to keep); without it nothing is touched.
   */
  private async serveFromCache(seq: number, scope: SessionScope | null, failMessage: string | null, clearOnMiss: boolean): Promise<boolean> {
    const snapshot = scope ? await this.offlineStore.get<unknown>('livestock') : null;
    if (seq !== this.requestSeq) return false;
    if (scope && !this.isCurrentScope(scope)) return false;

    let rows: Record<string, unknown>[] | null = null;
    if (snapshot && scope) {
      if (snapshotMatchesTenant(snapshot.data, scope.id_company)) {
        rows = snapshot.data;
      } else {
        // Defense in depth: discard the whole snapshot. Log without data contents.
        this.logger.warn('CattleData: offline snapshot discarded (tenant mismatch or invalid shape)');
      }
    }

    if (rows && snapshot) {
      this.cattleList.set(rows);
      this.hasLoadedOnce.set(true);
      this.loadError.set(null);
      this.servedFromCache.set(true);
      this.cacheSavedAt.set(snapshot.savedAt);
      return true;
    }

    if (failMessage) {
      if (clearOnMiss) this.cattleList.set([]);
      this.servedFromCache.set(false);
      this.cacheSavedAt.set(null);
      this.loadError.set(failMessage);
    }
    return false;
  }

  /** Fire-and-forget: a failed sanitize or put never affects the UI. */
  private storeSnapshot(rows: unknown, scope: SessionScope): void {
    try {
      const flagged = findFinancialLookingColumns(Array.isArray(rows) ? rows : []);
      const flaggedKey = flagged.join('|');
      if (flagged.length && flaggedKey !== this.lastFlaggedKey) {
        this.lastFlaggedKey = flaggedKey;
        // Column names only (never values). Logged once per distinct set of names per instance.
        // They are stored as-is; review before enabling offline.
        this.logger.warn('CattleData: financial-looking columns in livestock rows: ' + flagged.join(', '));
      }
      void this.offlineStore.put('livestock', sanitizeLivestockForOffline(rows), scope).catch(() => undefined);
    } catch {
      // swallowed on purpose
    }
  }

  private captureScope(): SessionScope | null {
    try {
      return this.auth.getSessionScope();
    } catch {
      return null;
    }
  }

  /** Fail-closed: an unreadable state counts as 'expired' (plain HTTP path, no cache). */
  private captureState(): SessionState {
    try {
      return this.auth.getSessionState();
    } catch {
      return 'expired';
    }
  }

  private isCurrentScope(scope: SessionScope): boolean {
    const now = this.captureScope();
    return !!now && now.user === scope.user && now.id_company === scope.id_company;
  }
}
