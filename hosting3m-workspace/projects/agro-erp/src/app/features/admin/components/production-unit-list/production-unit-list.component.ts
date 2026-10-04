import { Component, computed, effect, inject, signal, untracked } from '@angular/core';
import { toSignal } from '@angular/core/rxjs-interop';
import { map } from 'rxjs';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { TenantService } from 'core-auth';
import { ProductionUnitSummary } from '@core/models/production-unit-lot.model';
import { ProductionUnitLotService } from '@features/admin/services/production-unit-lot.service';
import { canManageProductionUnits } from '@features/admin/guards/active-tenant-route.guard';
import {
  ProductionUnitFormModalComponent,
  ProductionUnitFormState,
} from '../production-unit-form-modal/production-unit-form-modal.component';

/**
 * UPPs (`production_units`) of the ACTIVE tenant — entry point to each UPP's lots.
 * `activeTenantRouteGuard` already rejects a `:tenantId` other than the active one; the
 * effect below also leaves the page if the active tenant changes while it is open.
 */
@Component({
  selector: 'app-production-unit-list',
  standalone: true,
  imports: [CommonModule, FormsModule, RouterLink, ProductionUnitFormModalComponent],
  templateUrl: './production-unit-list.component.html',
})
export class ProductionUnitListComponent {
  private lotService = inject(ProductionUnitLotService);
  private tenantService = inject(TenantService);
  private router = inject(Router);
  private route = inject(ActivatedRoute);

  /** Route param. Display/navigation only — never sent to the API. */
  tenantId = toSignal(this.route.paramMap.pipe(map(p => p.get('tenantId'))));

  activeTenant = this.tenantService.activeTenant;
  canEdit = computed(() => canManageProductionUnits(this.tenantService.activeTenant()?.role));

  units = signal<ProductionUnitSummary[]>([]);
  isLoading = signal<boolean>(false);
  loadError = signal<string | null>(null);
  searchQuery = signal<string>('');

  // Edit modal
  isModalOpen = signal<boolean>(false);
  selectedUnit = signal<ProductionUnitSummary | null>(null);
  formData = signal<ProductionUnitFormState>(this.emptyForm());
  isSubmitting = signal<boolean>(false);
  formError = signal<string | null>(null);

  filteredUnits = computed(() => {
    const q = this.searchQuery().toLowerCase();
    return this.units().filter(u =>
      !q || u.ranchName.toLowerCase().includes(q) || u.uppCode.toLowerCase().includes(q)
    );
  });

  constructor() {
    effect(() => {
      const activeId = this.tenantService.activeTenantId();
      if (!activeId || String(activeId) !== String(this.tenantId() ?? activeId)) {
        untracked(() => this.router.navigate(['/admin/tenants']));
        return;
      }
      untracked(() => this.load());
    });
  }

  async load() {
    this.isLoading.set(true);
    this.loadError.set(null);
    try {
      this.units.set(await this.lotService.getProductionUnits());
    } catch (error: any) {
      console.error('[Agro-ERP] Error al cargar las UPP:', error);
      this.loadError.set(error?.message || 'No se pudieron cargar las unidades de producción.');
      this.units.set([]);
    } finally {
      this.isLoading.set(false);
    }
  }

  openEdit(unit: ProductionUnitSummary) {
    if (!this.canEdit()) return;
    this.selectedUnit.set(unit);
    this.formData.set({
      ranchName: unit.ranchName,
      uppCode: unit.uppCode,
      stateName: unit.stateName ?? '',
      municipalityName: unit.municipalityName ?? '',
      localityName: unit.localityName ?? ''
    });
    this.formError.set(null);
    this.isModalOpen.set(true);
  }

  closeModal() {
    if (this.isSubmitting()) return;
    this.isModalOpen.set(false);
    this.selectedUnit.set(null);
  }

  async saveUnit() {
    const unit = this.selectedUnit();
    if (!unit || !this.canEdit()) return;

    const data = this.formData();
    if (!data.ranchName.trim()) {
      this.formError.set('El nombre del rancho es obligatorio.');
      return;
    }

    this.isSubmitting.set(true);
    this.formError.set(null);
    try {
      await this.lotService.updateProductionUnit(unit.id, data);
      this.isModalOpen.set(false);
      this.selectedUnit.set(null);
      await this.load();
    } catch (error: any) {
      console.error('[Agro-ERP] Error al guardar la UPP oficial:', error);
      this.formError.set(error?.message || 'No se pudo guardar la UPP oficial.');
    } finally {
      this.isSubmitting.set(false);
    }
  }

  private emptyForm(): ProductionUnitFormState {
    return { ranchName: '', uppCode: '', stateName: '', municipalityName: '', localityName: '' };
  }
}
