import { ChangeDetectionStrategy, Component, computed, effect, inject, signal, untracked } from '@angular/core';
import { DecimalPipe } from '@angular/common';
import { Router, RouterLink } from '@angular/router';
import { TenantService } from 'core-auth';
import { Plantation, PlantationInput, PlantationSummary, TENURE_OPTIONS } from '@core/models/agri.model';
import { dashboardRouteFor, isPalmDomain } from '@shared/utils/business-domain.util';
import { AgriApiService } from '../services/agri-api.service';
import { PlantationContextService } from '../services/plantation-context.service';
import { canAdministerPalm, validatePlantationInput } from '../utils/agri.util';
import { PlantationFormModalComponent } from './plantation-form-modal.component';

type PlantationRow = Plantation & { summary: PlantationSummary | null };

/** Plantations of the active company (ADMIN / OWNER; palmAdminGuard). Nothing is deleted. */
@Component({
  selector: 'app-plantation-list',
  standalone: true,
  imports: [DecimalPipe, RouterLink, PlantationFormModalComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './plantation-list.component.html',
})
export class PlantationListComponent {
  private api = inject(AgriApiService);
  private context = inject(PlantationContextService);
  private tenantService = inject(TenantService);
  private router = inject(Router);

  activeTenant = this.tenantService.activeTenant;
  canEdit = computed(() => canAdministerPalm(this.tenantService.activeTenant()?.role));

  rows = signal<PlantationRow[]>([]);
  isLoading = signal(false);
  loadError = signal<string | null>(null);
  actionError = signal<string | null>(null);
  actionSuccess = signal<string | null>(null);
  possiblyTruncated = signal(false);
  busyId = signal<string | null>(null);
  activeCount = computed(() => this.rows().filter(r => r.isActive).length);

  isModalOpen = signal(false);
  editingId = signal<string | null>(null);
  formData = signal<PlantationInput>(this.emptyForm());
  isSubmitting = signal(false);
  formError = signal<string | null>(null);

  toDeactivate = signal<PlantationRow | null>(null);

  constructor() {
    effect(() => {
      const tenant = this.tenantService.activeTenant();
      if (!isPalmDomain(tenant)) {
        untracked(() => this.router.navigateByUrl(dashboardRouteFor(tenant)));
        return;
      }
      untracked(() => this.load());
    });
  }

  tenureLabel(value: string | null): string {
    return TENURE_OPTIONS.find(o => o.value === value)?.label ?? (value || '—');
  }

  async load() {
    this.isLoading.set(true);
    this.loadError.set(null);
    try {
      const [plantations, summaries] = await Promise.all([this.api.getPlantations(), this.api.getPlantationSummaries()]);
      const byId = new Map(summaries.items.map(s => [s.id, s]));
      this.rows.set(plantations.items.map(p => ({ ...p, summary: byId.get(p.id) ?? null })));
      this.possiblyTruncated.set(plantations.possiblyTruncated);
    } catch (error: any) {
      console.error('[Agro-ERP] Error al cargar las plantaciones:', error);
      this.rows.set([]);
      this.loadError.set(error?.message || 'No se pudieron cargar las plantaciones.');
    } finally {
      this.isLoading.set(false);
    }
  }

  private async afterChange(message: string) {
    this.actionSuccess.set(message);
    await Promise.all([this.load(), this.context.reload()]);
  }

  // Create / edit -----------------------------------------------------------------------------------

  openModal(row: PlantationRow | null = null) {
    if (!this.canEdit()) return;
    this.editingId.set(row?.id ?? null);
    this.formData.set(row ? {
      code: row.code, name: row.name, state: row.state ?? '', municipality: row.municipality ?? '',
      locality: row.locality ?? '', latitude: row.latitude?.toString() ?? '', longitude: row.longitude?.toString() ?? '',
      totalAreaHa: row.totalAreaHa.toString(), tenure: row.tenure, lessorName: row.lessorName ?? '', notes: row.notes ?? '',
    } : this.emptyForm());
    this.formError.set(null);
    this.actionSuccess.set(null);
    this.isModalOpen.set(true);
  }

  closeModal() {
    if (this.isSubmitting()) return;
    this.isModalOpen.set(false);
  }

  async save() {
    if (!this.canEdit()) return;
    const data = this.formData();
    const validation = validatePlantationInput(data) ?? this.codeConflict(data.code, this.editingId());
    if (validation) {
      this.formError.set(validation);
      return;
    }
    this.isSubmitting.set(true);
    this.formError.set(null);
    try {
      const id = this.editingId();
      if (id) await this.api.updatePlantation(id, data);
      else await this.api.createPlantation(data);
      this.isModalOpen.set(false);
      await this.afterChange(id ? 'Plantación actualizada.' : 'Plantación registrada.');
    } catch (error: any) {
      console.error('[Agro-ERP] Error al guardar la plantación:', error);
      this.formError.set(error?.message || 'No se pudo guardar la plantación.');
    } finally {
      this.isSubmitting.set(false);
    }
  }

  /** Same rule as uq_agri_plantations_code_active, checked locally first. */
  private codeConflict(code: string, excludeId: string | null): string | null {
    const key = code.trim().toUpperCase();
    const editing = this.rows().find(r => r.id === excludeId);
    if (editing && !editing.isActive) return null;
    return this.rows().some(r => r.isActive && r.id !== excludeId && r.code.trim().toUpperCase() === key)
      ? `Ya existe una plantación activa con la clave "${code.trim()}".` : null;
  }

  // Default / deactivate / reactivate ---------------------------------------------------------------

  async makeDefault(row: PlantationRow) {
    if (!this.canEdit() || !row.isActive || row.isDefault) return;
    this.actionError.set(null);
    this.actionSuccess.set(null);
    this.busyId.set(row.id);
    try {
      await this.api.setDefaultPlantation(row.id);
      await this.afterChange(`"${row.name}" es ahora la plantación predeterminada.`);
    } catch (error: any) {
      console.error('[Agro-ERP] Error al cambiar la plantación predeterminada:', error);
      this.actionError.set(error?.message || 'No se pudo cambiar la plantación predeterminada.');
    } finally {
      this.busyId.set(null);
    }
  }

  requestDeactivate(row: PlantationRow) {
    if (!this.canEdit()) return;
    this.actionError.set(null);
    this.actionSuccess.set(null);
    this.toDeactivate.set(row);
  }

  cancelDeactivate() {
    if (!this.busyId()) this.toDeactivate.set(null);
  }

  async confirmDeactivate() {
    const row = this.toDeactivate();
    if (!row) return;
    this.busyId.set(row.id);
    try {
      await this.api.setPlantationActive(row.id, false);
      this.toDeactivate.set(null);
      await this.afterChange(`"${row.name}" quedó inactiva.`);
    } catch (error: any) {
      console.error('[Agro-ERP] Error al desactivar la plantación:', error);
      this.toDeactivate.set(null);
      this.actionError.set(error?.message || 'No se pudo desactivar la plantación.');
    } finally {
      this.busyId.set(null);
    }
  }

  async reactivate(row: PlantationRow) {
    if (!this.canEdit()) return;
    this.actionError.set(null);
    this.actionSuccess.set(null);
    // Reactivating makes the code compete again among active plantations.
    if (this.rows().some(r => r.isActive && r.id !== row.id && r.code.trim().toUpperCase() === row.code.trim().toUpperCase())) {
      this.actionError.set(`No se puede reactivar: ya existe otra plantación activa con la clave "${row.code}".`);
      return;
    }
    this.busyId.set(row.id);
    try {
      await this.api.setPlantationActive(row.id, true);
      await this.afterChange(`"${row.name}" se reactivó.`);
    } catch (error: any) {
      console.error('[Agro-ERP] Error al reactivar la plantación:', error);
      this.actionError.set(error?.message || 'No se pudo reactivar la plantación.');
    } finally {
      this.busyId.set(null);
    }
  }

  private emptyForm(): PlantationInput {
    return { code: '', name: '', state: '', municipality: '', locality: '', latitude: '', longitude: '',
      totalAreaHa: '', tenure: 'PROPIA', lessorName: '', notes: '' };
  }
}
