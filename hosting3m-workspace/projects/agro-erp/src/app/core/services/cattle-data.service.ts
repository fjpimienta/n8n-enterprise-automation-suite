import { Injectable, inject, signal, effect } from '@angular/core';
import { CattleApiService } from './cattle-api.service';
import { TenantService } from 'core-auth';

@Injectable({
  providedIn: 'root'
})
export class CattleDataService {
  private cattleApi = inject(CattleApiService);
  private tenantService = inject(TenantService);

  // States reactivos globales del dominio ganadero
  public cattleList = signal<any[]>([]);
  public isLoading = signal<boolean>(false);

  // Último error de carga, para que un consumidor (ej. MainDashboardComponent) pueda mostrar
  // un estado de error explícito en vez de una tabla vacía indistinguible de "tenant sin hato".
  public loadError = signal<string | null>(null);

  // Se vuelve true tras el primer `.set()` exitoso y nunca regresa a false — permite distinguir
  // "0 animales reales" de "nunca llegamos a cargar datos reales" cuando la carga inicial falla.
  public hasLoadedOnce = signal<boolean>(false);

  // Guard de concurrencia "latest-wins": cada llamada obtiene un número de secuencia propio.
  // Si para cuando la respuesta llega ya se disparó una llamada más reciente (cambio de tenant,
  // un refresh manual/automático, etc.), la respuesta vieja se descarta sin tocar ningún signal
  // — nunca "gana" una respuesta tardía sobre una más reciente, sin importar el orden de llegada.
  private requestSeq = 0;
  // Conteo de llamadas en vuelo — permite que `isLoading` se apague solo cuando la ÚLTIMA
  // llamada pendiente termina, evitando que una llamada vieja apague el spinner mientras una
  // más nueva (ej. un segundo cambio de tenant disparado antes de que el primero resuelva)
  // todavía está en curso.
  private pendingRequests = 0;

  constructor() {
    // Orquestador del ciclo de vida de los datos basado en el contexto de la empresa.
    // Deliberadamente SIN guard de "ya hay una carga en curso": un cambio de tenant siempre
    // debe disparar una carga nueva — el guard de secuencia dentro de loadCattleData() es lo
    // que garantiza que la respuesta más reciente sea la que gane, nunca un "skip if busy" aquí.
    effect(() => {
      const tenantId = this.tenantService.activeTenantId();
      if (tenantId) {
        this.loadCattleData();
      }
    }, { allowSignalWrites: true });
  }

  /**
   * Ejecuta la petición HTTP hacia la capa Meta-CRUD a través de n8n
   * utilizando el contexto del Tenant activo actual.
   */
  public async loadCattleData(): Promise<void> {
    const seq = ++this.requestSeq;
    this.pendingRequests++;
    this.isLoading.set(true);
    try {
      const data = await this.cattleApi.getAllLivestock();
      if (seq !== this.requestSeq) return; // una llamada más reciente ya está en curso/resuelta — descartar

      this.cattleList.set(data || []);
      this.hasLoadedOnce.set(true);
      this.loadError.set(null);
    } catch (error: any) {
      if (seq !== this.requestSeq) return; // idem — no pisar un estado más nuevo con un error viejo

      console.error('Error crítico en el Data Pipeline de CattleDataService:', error);
      this.loadError.set(error?.message || 'No se pudo cargar el inventario de ganado.');
      // MetaCRUD Silent Error Shield: cattleList() NO se vacía — se conserva el último dato bueno.
    } finally {
      this.pendingRequests--;
      if (this.pendingRequests === 0) this.isLoading.set(false);
    }
  }
}