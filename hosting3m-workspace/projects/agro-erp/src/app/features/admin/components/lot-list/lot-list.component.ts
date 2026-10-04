import { Component, computed, effect, inject, signal, untracked } from '@angular/core';
import { toSignal } from '@angular/core/rxjs-interop';
import { map } from 'rxjs';
import { CommonModule } from '@angular/common';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { TenantService } from 'core-auth';
import {
  LOT_TENURE_OPTIONS,
  ProductionUnitLot,
  ProductionUnitSummary,
  lotNameKey,
} from '@core/models/production-unit-lot.model';
import {
  DuplicateLotNameError,
  ProductionUnitLotService,
  TenantContextError,
} from '@features/admin/services/production-unit-lot.service';
import { canManageLots } from '@features/admin/guards/active-tenant-route.guard';
import { LotFormModalComponent, LotFormState } from '../lot-form-modal/lot-form-modal.component';

/**
 * Lots (`production_unit_lots`) of one UPP of the active tenant. The `:uppId` route param
 * is never trusted: the UPP is re-read with a tenant-scoped `getone` and the page refuses
 * to render if it belongs to another tenant.
 */
@Component({
  selector: 'app-lot-list',
  standalone: true,
  imports: [CommonModule, RouterLink, LotFormModalComponent],
  templateUrl: './lot-list.component.html',
})
export class LotListComponent {
  private lotService = inject(ProductionUnitLotService);
  private tenantService = inject(TenantService);
  private router = inject(Router);
  private route = inject(ActivatedRoute);

  private params = toSignal(this.route.paramMap.pipe(
    map(p => ({ tenantId: p.get('tenantId'), uppId: p.get('uppId') }))
  ));

  tenantId = computed(() => this.params()?.tenantId ?? null);
  canEdit = computed(() => canManageLots(this.tenantService.activeTenant()?.role));

  unit = signal<ProductionUnitSummary | null>(null);
  lots = signal<ProductionUnitLot[]>([]);
  isLoading = signal<boolean>(false);
  loadError = signal<string | null>(null);
  actionError = signal<string | null>(null);
  busyLotId = signal<string | null>(null);

  activeCount = computed(() => this.lots().filter(l => l.isActive).length);

  // Form modal
  isModalOpen = signal<boolean>(false);
  selectedLot = signal<ProductionUnitLot | null>(null);
  formData = signal<LotFormState>(this.emptyForm());
  isSubmitting = signal<boolean>(false);
  formError = signal<string | null>(null);

  // Deactivation confirmation
  lotToDeactivate = signal<ProductionUnitLot | null>(null);

  constructor() {
    effect(() => {
      const activeId = this.tenantService.activeTenantId();
      const params = this.params();
      if (!params) return;
      if (!activeId || String(activeId) !== params.tenantId || !params.uppId) {
        untracked(() => this.router.navigate(['/admin/tenants']));
        return;
      }
      untracked(() => this.load(params.uppId!));
    });
  }

  tenureLabel(value: string): string {
    return LOT_TENURE_OPTIONS.find(o => o.value === value)?.label ?? value;
  }

  async load(uppId: string) {
    this.isLoading.set(true);
    this.loadError.set(null);
    try {
      const unit = await this.lotService.getProductionUnit(uppId);
      this.unit.set(unit);
      this.lots.set(await this.lotService.getLots(unit.id));
    } catch (error: any) {
      console.error('[Agro-ERP] Error al cargar los lotes:', error);
      this.unit.set(null);
      this.lots.set([]);
      this.loadError.set(error?.message || 'No se pudieron cargar los lotes de la UPP.');
    } finally {
      this.isLoading.set(false);
    }
  }

  private reload() {
    const unit = this.unit();
    if (unit) return this.load(unit.id);
    return Promise.resolve();
  }

  // ---------------------------------------------------------------------------
  // Create / edit
  // ---------------------------------------------------------------------------

  openModal(lot: ProductionUnitLot | null = null) {
    if (!this.canEdit()) return;
    this.selectedLot.set(lot);
    this.formData.set(lot ? {
      lotName: lot.lotName,
      tenureType: lot.tenureType,
      lessorName: lot.lessorName ?? '',
      locationNotes: lot.locationNotes ?? '',
      notes: lot.notes ?? ''
    } : this.emptyForm());
    this.formError.set(null);
    this.isModalOpen.set(true);
  }

  closeModal() {
    if (this.isSubmitting()) return;
    this.isModalOpen.set(false);
    this.selectedLot.set(null);
  }

  async saveLot() {
    const unit = this.unit();
    if (!unit || !this.canEdit()) return;

    const data = this.formData();
    const selected = this.selectedLot();
    const validation = this.validateForm(data, selected);
    if (validation) {
      this.formError.set(validation);
      return;
    }

    this.isSubmitting.set(true);
    this.formError.set(null);
    try {
      const payload = {
        lotName: data.lotName,
        tenureType: data.tenureType,
        lessorName: data.lessorName,
        locationNotes: data.locationNotes,
        notes: data.notes
      };
      if (selected) {
        await this.lotService.updateLot(selected.id, payload);
      } else {
        await this.lotService.createLot({ productionUnitId: unit.id, ...payload });
      }
      this.isModalOpen.set(false);
      this.selectedLot.set(null);
      await this.reload();
    } catch (error: any) {
      console.error('[Agro-ERP] Error al guardar el lote:', error);
      this.formError.set(this.describeError(error, 'No se pudo guardar el lote.'));
    } finally {
      this.isSubmitting.set(false);
    }
  }

  /** Mirrors the DB constraints so the user gets feedback before the round-trip. */
  private validateForm(data: LotFormState, selected: ProductionUnitLot | null): string | null {
    const name = data.lotName.trim();
    if (!name) return 'El nombre del lote es obligatorio.';
    if (name.length > 100) return 'El nombre del lote no puede exceder 100 caracteres.';
    if (!data.tenureType) return 'El tipo de tenencia es obligatorio.';
    if (data.tenureType === 'RENTADA' && !data.lessorName.trim()) {
      return 'El arrendador es obligatorio cuando la tenencia es Rentada.';
    }

    // Uniqueness applies only among ACTIVE lots; an inactive lot being edited does not compete.
    const competes = !selected || selected.isActive;
    if (competes && this.hasActiveNameConflict(name, selected?.id ?? null)) {
      return `Ya existe un lote activo llamado "${name}" en esta UPP.`;
    }
    return null;
  }

  private hasActiveNameConflict(name: string, excludeId: string | null): boolean {
    const key = lotNameKey(name);
    return this.lots().some(l => l.isActive && l.id !== excludeId && lotNameKey(l.lotName) === key);
  }

  // ---------------------------------------------------------------------------
  // Deactivate (soft-delete) / reactivate
  // ---------------------------------------------------------------------------

  requestDeactivate(lot: ProductionUnitLot) {
    if (!this.canEdit()) return;
    this.actionError.set(null);
    this.lotToDeactivate.set(lot);
  }

  cancelDeactivate() {
    if (this.busyLotId()) return;
    this.lotToDeactivate.set(null);
  }

  async confirmDeactivate() {
    const lot = this.lotToDeactivate();
    if (!lot) return;
    this.busyLotId.set(lot.id);
    try {
      await this.lotService.deactivateLot(lot.id);
      this.lotToDeactivate.set(null);
      await this.reload();
    } catch (error: any) {
      console.error('[Agro-ERP] Error al desactivar el lote:', error);
      this.lotToDeactivate.set(null);
      this.actionError.set(this.describeError(error, 'No se pudo desactivar el lote.'));
    } finally {
      this.busyLotId.set(null);
    }
  }

  async reactivate(lot: ProductionUnitLot) {
    if (!this.canEdit()) return;
    this.actionError.set(null);

    if (this.hasActiveNameConflict(lot.lotName, lot.id)) {
      this.actionError.set(
        `No se puede reactivar "${lot.lotName}": ya existe otro lote activo con ese nombre en esta UPP. ` +
        'Renombra o desactiva el otro lote primero.'
      );
      return;
    }

    this.busyLotId.set(lot.id);
    try {
      await this.lotService.reactivateLot(lot.id);
      await this.reload();
    } catch (error: any) {
      console.error('[Agro-ERP] Error al reactivar el lote:', error);
      this.actionError.set(this.describeError(error, 'No se pudo reactivar el lote.'));
    } finally {
      this.busyLotId.set(null);
    }
  }

  private describeError(error: unknown, fallback: string): string {
    if (error instanceof DuplicateLotNameError || error instanceof TenantContextError) return error.message;
    return (error as any)?.message || fallback;
  }

  private emptyForm(): LotFormState {
    return { lotName: '', tenureType: 'PROPIO', lessorName: '', locationNotes: '', notes: '' };
  }
}
