import { Injectable, computed, effect, inject, signal, untracked } from '@angular/core';
import { AuthService, TenantService } from 'core-auth';
import { Plantation } from '@core/models/agri.model';
import { isPalmDomain } from '@shared/utils/business-domain.util';
import { AgriApiService } from './agri-api.service';
import {
  StorageLike,
  clearStoredPlantations,
  readStoredPlantation,
  resolveActivePlantation,
  writeStoredPlantation,
} from '../utils/plantation-context.util';

export type PlantationContextStatus = 'idle' | 'loading' | 'ready' | 'error';

/**
 * Active plantation of the active palm company (UI scope filter only: the security boundary stays
 * id_company, and every screen re-validates ids against the server).
 *
 * - When the active company changes the context is cleared at once (never shows the previous company's
 *   plantation), then reloaded from the server; responses that arrive for a company that is no longer
 *   active are discarded.
 * - Resolution: last choice for that company if still active -> company default -> any other active
 *   plantation -> null. A stored id that is not in the server list is ignored (fail-closed).
 * - The choice is persisted per company (`agri_active_plantation:<id_company>`), every storage access in
 *   try/catch. Logout clears the in-memory context and every stored choice (no inherited context, see the
 *   2026-10-04 Context Switcher incident in the CHANGELOG).
 */
@Injectable({ providedIn: 'root' })
export class PlantationContextService {
  private tenantService = inject(TenantService);
  private authService = inject(AuthService);
  private api = inject(AgriApiService);

  private readonly _plantations = signal<Plantation[]>([]);
  private readonly _activeId = signal<string | null>(null);
  private readonly _status = signal<PlantationContextStatus>('idle');
  private readonly _error = signal<string | null>(null);
  private requestSeq = 0;

  readonly status = this._status.asReadonly();
  readonly error = this._error.asReadonly();
  readonly isPalmCompany = computed(() => isPalmDomain(this.tenantService.activeTenant()));
  /** Every plantation of the company (active and inactive), as returned by the server. */
  readonly allPlantations = this._plantations.asReadonly();
  /** Plantations that can be selected. */
  readonly availablePlantations = computed(() => this._plantations().filter(p => p.isActive));
  readonly activePlantationId = computed(() => {
    const id = this._activeId();
    return id && this.availablePlantations().some(p => p.id === id) ? id : null;
  });
  readonly activePlantation = computed(() =>
    this.availablePlantations().find(p => p.id === this.activePlantationId()) ?? null);

  constructor() {
    effect(() => {
      const tenantId = this.tenantService.activeTenantId();
      const palm = this.isPalmCompany();
      untracked(() => this.switchTo(palm && tenantId ? Number(tenantId) : null));
    });
    effect(() => {
      if (!this.authService.isAuthenticated()) untracked(() => clearStoredPlantations(this.storage()));
    });
  }

  /** Reloads the plantations of the active company (after creating / editing / deactivating one). */
  reload(): Promise<void> {
    const tenantId = this.currentPalmTenant();
    return tenantId ? this.load(tenantId) : Promise.resolve();
  }

  /** Makes a plantation active. Only ids present in the server list (and active) are accepted. */
  select(plantationId: string): boolean {
    const tenantId = this.currentPalmTenant();
    if (!tenantId || !this.availablePlantations().some(p => p.id === plantationId)) return false;
    this._activeId.set(plantationId);
    writeStoredPlantation(this.storage(), tenantId, plantationId);
    return true;
  }

  private switchTo(tenantId: number | null): void {
    this.requestSeq++;
    this._plantations.set([]);
    this._activeId.set(null);
    this._error.set(null);
    this._status.set('idle');
    if (tenantId) void this.load(tenantId);
  }

  private async load(tenantId: number): Promise<void> {
    const seq = ++this.requestSeq;
    this._status.set('loading');
    this._error.set(null);
    try {
      const { items } = await this.api.getPlantations();
      if (seq !== this.requestSeq || this.currentPalmTenant() !== tenantId) return; // stale response
      this._plantations.set(items);
      const stored = readStoredPlantation(this.storage(), tenantId);
      const resolved = resolveActivePlantation(items, stored);
      this._activeId.set(resolved);
      // A stored choice that is no longer valid is forgotten; defaults are never pinned as a choice.
      if (stored && stored !== resolved) writeStoredPlantation(this.storage(), tenantId, null);
      this._status.set('ready');
    } catch (error: any) {
      if (seq !== this.requestSeq) return;
      console.error('[Agro-ERP] Error al cargar las plantaciones:', error);
      this._plantations.set([]);
      this._activeId.set(null);
      this._error.set(error?.message || 'No se pudieron cargar las plantaciones.');
      this._status.set('error');
    }
  }

  private currentPalmTenant(): number | null {
    const id = Number(this.tenantService.activeTenantId());
    return this.isPalmCompany() && Number.isInteger(id) && id > 0 ? id : null;
  }

  private storage(): StorageLike | null {
    try {
      return typeof localStorage !== 'undefined' ? localStorage : null;
    } catch {
      return null;
    }
  }
}
