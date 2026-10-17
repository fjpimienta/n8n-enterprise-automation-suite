import { ChangeDetectionStrategy, Component, computed, effect, inject, signal, untracked } from '@angular/core';
import { DecimalPipe } from '@angular/common';
import { RouterLink } from '@angular/router';
import { TenantService } from 'core-auth';
import { Lot, LotInput, LotSummary, STAGE_OPTIONS, TENURE_OPTIONS, Variety } from '@core/models/agri.model';
import { AgriApiService } from '../services/agri-api.service';
import { PlantationContextService } from '../services/plantation-context.service';
import { canAdministerPalm, todayCdmx, validateLotInput } from '../utils/agri.util';
import { AgriLotFormModalComponent } from './agri-lot-form-modal.component';

/**
 * Lots of the ACTIVE plantation. Every palm role can see them (EDITOR reaches the rows from here to record
 * counts); creating, editing and deactivating is ADMIN / OWNER. Stage, effective tenure and counts come
 * from vw_agri_lot_summary (nothing is computed and persisted in the client).
 */
@Component({
  selector: 'app-agri-lot-list',
  standalone: true,
  imports: [DecimalPipe, RouterLink, AgriLotFormModalComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './agri-lot-list.component.html',
})
export class AgriLotListComponent {
  private api = inject(AgriApiService);
  private tenantService = inject(TenantService);
  context = inject(PlantationContextService);

  canEdit = computed(() => canAdministerPalm(this.tenantService.activeTenant()?.role));
  plantation = this.context.activePlantation;

  lots = signal<LotSummary[]>([]);
  rawLots = signal<Lot[]>([]);
  varieties = signal<Variety[]>([]);
  isLoading = signal(false);
  loadError = signal<string | null>(null);
  actionError = signal<string | null>(null);
  actionSuccess = signal<string | null>(null);
  possiblyTruncated = signal(false);
  busyId = signal<string | null>(null);
  activeCount = computed(() => this.lots().filter(l => l.isActive).length);
  today = todayCdmx();

  isModalOpen = signal(false);
  editingId = signal<string | null>(null);
  formData = signal<LotInput>(this.emptyForm());
  isSubmitting = signal(false);
  formError = signal<string | null>(null);

  toDeactivate = signal<LotSummary | null>(null);

  constructor() {
    effect(() => {
      const plantationId = this.context.activePlantationId();
      untracked(() => {
        this.lots.set([]);
        this.rawLots.set([]);
        if (plantationId) void this.load(plantationId);
      });
    });
  }

  stageLabel(value: string) { return STAGE_OPTIONS.find(s => s.value === value)?.label ?? value; }
  stageBadge(value: string) { return STAGE_OPTIONS.find(s => s.value === value)?.badge ?? 'bg-secondary-lt'; }
  tenureLabel(value: string | null) { return TENURE_OPTIONS.find(o => o.value === value)?.label ?? (value || '—'); }

  async load(plantationId = this.context.activePlantationId()) {
    if (!plantationId) return;
    this.isLoading.set(true);
    this.loadError.set(null);
    try {
      const [summaries, lots, varieties] = await Promise.all([
        this.api.getLotSummaries(plantationId), this.api.getLots(plantationId),
        this.varieties().length ? Promise.resolve(this.varieties()) : this.api.getVarieties(),
      ]);
      if (this.context.activePlantationId() !== plantationId) return; // plantation switched meanwhile
      this.lots.set(summaries.items);
      this.rawLots.set(lots.items);
      this.varieties.set(varieties);
      this.possiblyTruncated.set(summaries.possiblyTruncated || lots.possiblyTruncated);
    } catch (error: any) {
      console.error('[Agro-ERP] Error al cargar los lotes:', error);
      this.lots.set([]);
      this.loadError.set(error?.message || 'No se pudieron cargar los lotes.');
    } finally {
      this.isLoading.set(false);
    }
  }

  // Create / edit -----------------------------------------------------------------------------------

  openModal(summary: LotSummary | null = null) {
    if (!this.canEdit()) return;
    const lot = summary ? this.rawLots().find(l => l.id === summary.id) : null;
    if (summary && !lot) {
      this.actionError.set('No se encontró el lote; vuelve a cargar la lista.');
      return;
    }
    this.editingId.set(lot?.id ?? null);
    this.formData.set(lot ? {
      code: lot.code, name: lot.name ?? '', areaHa: lot.areaHa.toString(), plantingDate: lot.plantingDate ?? '',
      plantingDateIsApprox: lot.plantingDateIsApprox, varietyId: lot.varietyId ?? '', seedSupplier: lot.seedSupplier ?? '',
      plantingPattern: lot.plantingPattern ?? '', spacingM: lot.spacingM?.toString() ?? '',
      designDensityPlantsHa: lot.designDensityPlantsHa?.toString() ?? '', waterRegime: lot.waterRegime ?? '',
      soilType: lot.soilType ?? '', tenure: lot.tenure ?? '', lessorName: lot.lessorName ?? '', notes: lot.notes ?? '',
    } : this.emptyForm());
    this.formError.set(null);
    this.actionSuccess.set(null);
    this.isModalOpen.set(true);
  }

  closeModal() {
    if (!this.isSubmitting()) this.isModalOpen.set(false);
  }

  async save() {
    const plantation = this.plantation();
    if (!plantation || !this.canEdit()) return;
    const data = this.formData();
    const validation = validateLotInput(data, this.today) ?? this.codeConflict(data.code, this.editingId());
    if (validation) {
      this.formError.set(validation);
      return;
    }
    this.isSubmitting.set(true);
    this.formError.set(null);
    try {
      const id = this.editingId();
      if (id) await this.api.updateLot(id, data);
      else await this.api.createLot(plantation.id, data);
      this.isModalOpen.set(false);
      this.actionSuccess.set(id ? 'Lote actualizado.' : 'Lote registrado.');
      await this.load();
    } catch (error: any) {
      console.error('[Agro-ERP] Error al guardar el lote:', error);
      this.formError.set(error?.message || 'No se pudo guardar el lote.');
    } finally {
      this.isSubmitting.set(false);
    }
  }

  private codeConflict(code: string, excludeId: string | null): string | null {
    const editing = this.lots().find(l => l.id === excludeId);
    if (editing && !editing.isActive) return null;
    const key = code.trim().toUpperCase();
    return this.lots().some(l => l.isActive && l.id !== excludeId && l.code.trim().toUpperCase() === key)
      ? `Ya existe un lote activo con la clave "${code.trim()}" en esta plantación.` : null;
  }

  // Deactivate / reactivate ------------------------------------------------------------------------

  requestDeactivate(lot: LotSummary) {
    if (!this.canEdit()) return;
    this.actionError.set(null);
    this.actionSuccess.set(null);
    this.toDeactivate.set(lot);
  }

  cancelDeactivate() {
    if (!this.busyId()) this.toDeactivate.set(null);
  }

  async confirmDeactivate() {
    const lot = this.toDeactivate();
    if (!lot) return;
    this.busyId.set(lot.id);
    try {
      await this.api.setLotActive(lot.id, false);
      this.toDeactivate.set(null);
      this.actionSuccess.set(`El lote ${lot.code} quedó inactivo.`);
      await this.load();
    } catch (error: any) {
      console.error('[Agro-ERP] Error al desactivar el lote:', error);
      this.toDeactivate.set(null);
      this.actionError.set(error?.message || 'No se pudo desactivar el lote.');
    } finally {
      this.busyId.set(null);
    }
  }

  async reactivate(lot: LotSummary) {
    if (!this.canEdit()) return;
    this.actionError.set(null);
    this.actionSuccess.set(null);
    if (this.lots().some(l => l.isActive && l.id !== lot.id && l.code.trim().toUpperCase() === lot.code.trim().toUpperCase())) {
      this.actionError.set(`No se puede reactivar: ya existe otro lote activo con la clave "${lot.code}".`);
      return;
    }
    this.busyId.set(lot.id);
    try {
      await this.api.setLotActive(lot.id, true);
      this.actionSuccess.set(`El lote ${lot.code} se reactivó.`);
      await this.load();
    } catch (error: any) {
      console.error('[Agro-ERP] Error al reactivar el lote:', error);
      this.actionError.set(error?.message || 'No se pudo reactivar el lote.');
    } finally {
      this.busyId.set(null);
    }
  }

  private emptyForm(): LotInput {
    return { code: '', name: '', areaHa: '', plantingDate: '', plantingDateIsApprox: false, varietyId: '', seedSupplier: '',
      plantingPattern: '', spacingM: '', designDensityPlantsHa: '', waterRegime: '', soilType: '', tenure: '', lessorName: '', notes: '' };
  }
}
