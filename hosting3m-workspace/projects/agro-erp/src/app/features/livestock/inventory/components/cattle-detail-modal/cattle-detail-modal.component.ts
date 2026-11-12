import { Component, inject, Input, Output, EventEmitter, signal, computed, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormBuilder, FormGroup, Validators, ReactiveFormsModule } from '@angular/forms';
import { CattleApiService } from '@core/services/cattle-api.service';
import { ExpenseModalComponent } from '../../../expenses/components/expense-modal/expense-modal.component';
import { KpiCardComponent } from '@shared/expenses-ui/kpi-card.component';
import { formatMoney } from '@shared/expenses-ui/expenses-ui.util';
import { REFERENCE_PRICE_PER_KG, categoryLabel } from '../../../expenses/livestock-expense.util';
import { TenantService } from 'core-auth';
import { ProductionUnitLotService } from '@features/admin/services/production-unit-lot.service';
import { PANEL_LIVESTOCK_ALTA_ENABLED } from '../../../panel-livestock.switch';
import { canUsePanelAlta, todayInMexicoCity } from '../../../panel-livestock.util';
import {
  PanelLivestockInput,
  PanelLivestockIssue,
  PanelLivestockOptions,
  PanelLivestockResponse,
  PanelLivestockStatus,
  PanelLivestockWarning
} from '../../../models/panel-livestock.model';

/** Steps of the panel ALTA flow. `blocked` = hard/soft duplicate or forbidden; `error` = nothing was confirmed. */
export type PanelPhase = 'editing' | 'checking' | 'previewing' | 'saving' | 'saved' | 'blocked' | 'error';
export type PanelBlockKind = 'duplicate' | 'duplicate_other_company' | 'exists_without_upp' | 'duplicate_recent' | 'forbidden';

export const PANEL_FORBIDDEN_MESSAGE = 'Tu rol no permite dar de alta animales.';
export const PANEL_NO_TENANT_MESSAGE = 'No hay un rancho activo claro. Selecciona la empresa en la que vas a registrar el animal.';
export const PANEL_SAVED_MESSAGE = 'Animal registrado.';

function assertNever(value: never): never {
  throw new Error(`Estado no manejado del alta de ganado: ${String(value)}`);
}

@Component({
  selector: 'app-cattle-detail-modal',
  standalone: true,
  imports: [CommonModule, ReactiveFormsModule, ExpenseModalComponent, KpiCardComponent],
  templateUrl: './cattle-detail-modal.component.html',
  styleUrls: ['./cattle-detail-modal.component.scss']
})
export class CattleDetailModalComponent implements OnInit {
  private fb = inject(FormBuilder);
  private cattleApi = inject(CattleApiService);
  private tenantService = inject(TenantService);
  private unitService = inject(ProductionUnitLotService);

  @Input() actionType: 'ALTA' | 'SALUD' | 'PESO' | 'EDITAR' | 'COSTOS' | 'SALIDA' = 'ALTA';
  @Input() selectedRfid: string = '';
  @Input() livestockId: string = '';
  @Input() selectedAnimal: any = null;
  @Output() close = new EventEmitter<boolean>();

  public isSaving = signal<boolean>(false);

  /** Read once from the code switch. OFF = legacy ALTA flow, untouched. */
  public panelFlow: boolean = PANEL_LIVESTOCK_ALTA_ENABLED;
  private today = new Date().toISOString().split('T')[0];

  // Estado del sub-módulo COSTOS
  public animalExpenses = signal<any[]>([]);
  public loadingCosts = signal(false);
  public showSubExpenseModal = signal(false);

  public totalCost = computed(() =>
    this.animalExpenses().reduce((sum, e) => sum + Number(e.amount || 0), 0)
  );

  // COSTOS tab presentation (same data as before; the price is the dashboard's reference price).
  public readonly money = formatMoney;
  public readonly refPrice = REFERENCE_PRICE_PER_KG;
  public readonly categoryLabel = categoryLabel;
  public weightKg = computed(() => {
    const w = Number(this.selectedAnimal?.current_weight_kg || 0);
    return Number.isFinite(w) && w > 0 ? w : 0;
  });
  public estimatedValue = computed(() => this.weightKg() * REFERENCE_PRICE_PER_KG);
  public costBalance = computed(() => this.estimatedValue() - this.totalCost());

  public costPerKg = computed(() => {
    const weight = Number(this.selectedAnimal?.current_weight_kg || 0);
    return weight > 0 ? this.totalCost() / weight : 0;
  });

  // Referencia visual (no autoritativa) de vigencia normativa TB/BR. La validación real la hace el SP.
  public diasDesde(fecha?: string): number | null {
    if (!fecha) return null;
    return Math.floor((Date.now() - new Date(fecha).getTime()) / 86400000);
  }

  // Postgres rechaza '' en columnas date ("invalid input syntax for type date").
  // Los selects/inputs opcionales del form mandan '' cuando quedan vacíos; se normalizan a null.
  private sanitizeDates(payload: any): any {
    return {
      ...payload,
      tb_test_date: payload.tb_test_date || null,
      br_test_date: payload.br_test_date || null
    };
  }

  public altaForm: FormGroup = this.fb.group({
    rfid_siniiga: ['S/N', [Validators.required]], // Por defecto S/N
    numero_fuego: [''], // 🐂 NUEVO: Número interno o de fierro
    electronic_rfid: ['', [Validators.minLength(15)]],
    business_model: ['CRIA', Validators.required],
    category: ['VACA', Validators.required],
    current_status: ['ACTIVO', Validators.required],
    current_weight_kg: ['', [Validators.required, Validators.min(1)]],
    birth_date: [this.today, Validators.required],
    upp_origen: [''],
    tb_test_date: [''],
    br_test_date: ['']
  });

  public saludForm: FormGroup = this.fb.group({
    livestock_id: [''],
    rfid_siniiga: [{ value: '', disabled: true }, Validators.required],
    event_type: ['VACUNACION', Validators.required],
    event_date: [this.today, Validators.required],
    description: [''],
    // 🩺 NUEVOS CAMPOS CLÍNICOS PARA REPRODUCCIÓN (Mapeados del Excel)
    dx_resultado: ['VACIA'], // 'VACIA' o 'PREÑADA'
    dx_dias_gestacion: [0], // Ej. 120 (Si está preñada)
    dx_condicion: ['UNE'], // UNE, UT, etc.
    dx_ovario: ['N/A'] // OI, OD, N/A
  });

  public pesoForm: FormGroup = this.fb.group({
    livestock_id: [''],
    rfid_siniiga: [{ value: '', disabled: true }, Validators.required],
    weight_kg: ['', [Validators.required, Validators.min(1)]],
    log_date: [this.today, Validators.required]
  });

  public editForm: FormGroup = this.fb.group({
    rfid_siniiga: ['', Validators.required],
    numero_fuego: [''],
    electronic_rfid: ['', [Validators.minLength(15)]],
    business_model: ['CRIA', Validators.required],
    category: ['VACA', Validators.required],
    current_status: ['ACTIVO', Validators.required],
    current_weight_kg: ['', [Validators.required, Validators.min(1)]],
    birth_date: ['', Validators.required],
    upp_origen: [''],
    tb_test_date: [''],
    br_test_date: ['']
  });

  // ───────────────────────── Panel ALTA flow (behind PANEL_LIVESTOCK_ALTA_ENABLED) ─────────────────────────
  // editing → checking → previewing → saving → saved, plus blocked / error. `isSubmitting` is checked at the
  // START of every action (a disabled button is not enough against a fast double click or Enter). No retries.
  public readonly panelCategories = ['VACA', 'TORO', 'NOVILLO', 'BECERRA'];
  public readonly panelSpecies = ['BOVINO', 'EQUINO', 'OVINO', 'CAPRINO', 'PORCINO'];

  public phase = signal<PanelPhase>('editing');
  public isSubmitting = signal<boolean>(false);
  public success = signal<string | null>(null);
  public error = signal<string | null>(null);
  /** Message of palm / invalid answers: the user stays in step 1. */
  public formMessage = signal<string | null>(null);
  public issues = signal<PanelLivestockIssue[]>([]);
  public fieldErrors = signal<Record<string, string>>({});
  public warnings = signal<PanelLivestockWarning[]>([]);
  public preview = signal<Record<string, unknown> | null>(null);
  public previewNotice = signal<string | null>(null);
  public blockKind = signal<PanelBlockKind | null>(null);
  public blockMessage = signal<string | null>(null);
  public existingAnimal = signal<Record<string, unknown> | null>(null);
  public uppOptions = signal<{ value: string; label: string }[]>([]);
  public uppOptionsLoaded = signal<boolean>(false);
  private previewHash = '';

  public panelForm: FormGroup = this.fb.group({
    upp: [''],
    lot: [''],
    species: ['BOVINO'],
    category: ['VACA'],
    business_model: ['CRIA'],
    ear_tag: [''], // empty = no tag (the old 'S/N' literal is not sent)
    fire_number: [''],
    electronic_rfid: [''],
    weight_kg: [''],
    birth_date: [todayInMexicoCity()],
    origin_upp: [''],
    tb_test_date: [''],
    br_test_date: [''],
    notes: ['']
  });

  /** UPP options offered by the SP's `need_info` for the `upp` field. */
  public uppIssueOptions = computed(() => {
    const issue = this.issues().find(i => i.field === 'upp' && Array.isArray(i.options) && i.options.length > 0);
    return (issue?.options ?? []).map(o => {
      const opt = (o ?? {}) as Record<string, unknown>;
      const code = String(opt['upp_code'] ?? '');
      const name = String(opt['upp'] ?? code);
      return { value: code || name, label: code && name !== code ? `${name} (${code})` : name };
    });
  });

  /** Issues whose field has no control in the form: shown in a general list. */
  public generalIssues = computed(() =>
    this.issues().filter(i => !(i.field in this.panelForm.controls))
  );

  public previewRows = computed(() =>
    Object.entries(this.preview() ?? {}).map(([key, value]) => ({ key, label: this.previewLabel(key), value: this.previewValue(value) }))
  );

  public existingRows = computed(() =>
    Object.entries(this.existingAnimal() ?? {}).map(([key, value]) => ({ key, label: this.previewLabel(key), value: this.previewValue(value) }))
  );

  private static readonly PREVIEW_LABELS: Record<string, string> = {
    empresa: 'Empresa', upp: 'UPP', upp_code: 'Clave UPP', lote: 'Lote', especie: 'Especie', categoria: 'Categoría',
    modelo_negocio: 'Modelo de negocio', arete: 'Arete', sin_arete_oficial: 'Sin arete oficial', numero_fuego: 'Nº a fuego',
    rfid_electronico: 'Chip RFID', peso_kg: 'Peso (kg)', fecha_nacimiento: 'Fecha de nacimiento', upp_origen: 'UPP de origen',
    prueba_tb: 'Prueba TB', prueba_br: 'Prueba brucelosis', notas: 'Notas', category: 'Categoría', current_status: 'Estado',
    campo: 'Campo', identificador: 'Identificador'
  };

  private previewLabel(key: string): string {
    return CattleDetailModalComponent.PREVIEW_LABELS[key] ?? key;
  }

  private previewValue(value: unknown): string {
    if (value === true) return 'Sí';
    if (value === false) return 'No';
    return value === null || value === undefined ? '' : String(value);
  }

  /** Role of the ACTIVE tenant (same source as cattle-list); the gateway re-checks it. */
  public canUsePanel = computed(() => canUsePanelAlta(this.tenantService.activeTenant()?.role));

  public issueFor(field: string): PanelLivestockIssue | undefined {
    return this.issues().find(i => i.field === field);
  }

  public fieldError(field: string): string | null {
    return this.fieldErrors()[field] ?? this.issueFor(field)?.message ?? null;
  }

  public pickUpp(value: string): void {
    this.panelForm.patchValue({ upp: value });
    this.issues.set(this.issues().filter(i => i.field !== 'upp'));
  }

  private get hasActiveTenant(): boolean {
    const id = this.tenantService.activeTenantId();
    return id !== null && id !== undefined && String(id).trim() !== '';
  }

  private async loadPanelUpps(): Promise<void> {
    try {
      const units = await this.unitService.getProductionUnits();
      this.uppOptions.set(
        units.filter(u => u.isActive).map(u => ({ value: u.uppCode, label: `${u.ranchName} (${u.uppCode})` }))
      );
    } catch {
      // Not fatal: with several UPPs the SP answers need_info with the options.
      this.uppOptions.set([]);
    } finally {
      this.uppOptionsLoaded.set(true);
    }
  }

  private resetOutcome(): void {
    this.error.set(null);
    this.formMessage.set(null);
    this.issues.set([]);
    this.fieldErrors.set({});
    this.blockKind.set(null);
    this.blockMessage.set(null);
    this.existingAnimal.set(null);
  }

  private panelInput(): PanelLivestockInput {
    return this.panelForm.getRawValue() as PanelLivestockInput;
  }

  /** Step 1 → SP with confirmed=false. */
  public async review(): Promise<void> {
    if (this.isSubmitting()) return;
    if (this.phase() !== 'editing') return;
    this.resetOutcome();
    if (!this.canUsePanel()) return this.blockForbidden();
    if (!this.hasActiveTenant) return this.fail(PANEL_NO_TENANT_MESSAGE);

    this.isSubmitting.set(true);
    this.phase.set('checking');
    try {
      const res = await this.cattleApi.registerLivestockPanel(this.panelInput());
      this.handleResponse(res);
    } catch (e: any) {
      this.handleFailure(e, 'review');
    } finally {
      this.isSubmitting.set(false);
    }
  }

  /** Step 2 → SP with confirmed=true and the hash of the preview the user is looking at. */
  public async confirm(): Promise<void> {
    if (this.isSubmitting()) return;
    if (this.phase() !== 'previewing' || !this.previewHash) return;
    await this.send({ confirm: true, previewHash: this.previewHash });
  }

  /** duplicate_recent only: the user says it is another animal. Reuses the current preview hash. */
  public async registerAnyway(): Promise<void> {
    if (this.isSubmitting()) return;
    if (this.phase() !== 'blocked' || this.blockKind() !== 'duplicate_recent' || !this.previewHash) return;
    await this.send({ confirm: true, previewHash: this.previewHash, forceDuplicate: true });
  }

  private async send(opts: PanelLivestockOptions): Promise<void> {
    this.resetOutcome();
    if (!this.canUsePanel()) return this.blockForbidden();
    if (!this.hasActiveTenant) return this.fail(PANEL_NO_TENANT_MESSAGE);

    this.isSubmitting.set(true);
    this.phase.set('saving');
    try {
      const res = await this.cattleApi.registerLivestockPanel(this.panelInput(), opts);
      this.handleResponse(res);
    } catch (e: any) {
      this.handleFailure(e, 'confirm');
    } finally {
      this.isSubmitting.set(false);
    }
  }

  public backToEditing(): void {
    if (this.isSubmitting()) return;
    this.previewHash = '';
    this.preview.set(null);
    this.warnings.set([]);
    this.previewNotice.set(null);
    this.resetOutcome();
    this.phase.set('editing');
  }

  private handleFailure(e: any, step: 'review' | 'confirm'): void {
    const message: string = e?.message || 'Error de conexión';
    // The service rejects a non-numeric weight before sending anything: show it next to the field.
    if (step === 'review' && /peso/i.test(message)) {
      this.fieldErrors.set({ weight_kg: message });
      this.phase.set('editing');
      return;
    }
    this.fail(message);
  }

  private fail(message: string): void {
    // Whatever happened, nothing is confirmed: never success. The hash is dropped so a retry needs a new preview.
    this.previewHash = '';
    this.error.set(message);
    this.phase.set('error');
  }

  private blockForbidden(): void {
    this.blockKind.set('forbidden');
    this.blockMessage.set(PANEL_FORBIDDEN_MESSAGE);
    this.phase.set('blocked');
  }

  private handleResponse(res: PanelLivestockResponse): void {
    const status: PanelLivestockStatus = res?.status;
    switch (status) {
      case 'preview':
      case 'preview_required': {
        if (!res.preview_hash || !res.preview) return this.fail('El servidor no devolvió la vista previa del alta.');
        this.previewHash = res.preview_hash;
        this.preview.set(res.preview);
        this.warnings.set(res.warnings ?? []);
        this.previewNotice.set(status === 'preview_required' ? (res.message ?? 'Los datos cambiaron: revisa la nueva vista previa.') : null);
        this.phase.set('previewing');
        return;
      }
      case 'recorded': {
        if (!res.livestock_id) return this.fail('El servidor no confirmó el alta del animal.');
        this.previewHash = '';
        this.success.set(res.message || PANEL_SAVED_MESSAGE);
        this.phase.set('saved');
        this.closeModal(true);
        return;
      }
      case 'need_info': {
        const issues = res.issues ?? [];
        this.previewHash = '';
        this.issues.set(issues);
        this.formMessage.set(issues.length ? null : (res.message ?? 'Faltan datos para registrar el animal.'));
        this.phase.set('editing');
        return;
      }
      case 'duplicate':
      case 'duplicate_other_company':
      case 'exists_without_upp':
        this.block(status, res);
        return;
      case 'duplicate_recent':
        // Keep the hash of the preview already shown: this answer does not carry a new one.
        this.block(status, res);
        return;
      case 'forbidden':
        this.blockKind.set('forbidden');
        this.blockMessage.set(PANEL_FORBIDDEN_MESSAGE);
        this.phase.set('blocked');
        return;
      case 'palm':
      case 'invalid':
        this.previewHash = '';
        this.formMessage.set(res.message || 'No se pudo registrar el animal con estos datos.');
        this.phase.set('editing');
        return;
      default:
        return assertNever(status);
    }
  }

  private block(kind: Exclude<PanelBlockKind, 'forbidden'>, res: PanelLivestockResponse): void {
    if (kind !== 'duplicate_recent') this.previewHash = '';
    this.blockKind.set(kind);
    this.blockMessage.set(res.message || 'Este animal ya está registrado.');
    // Existing animal data the procedure returned (never anything about another company).
    const known = ['category', 'current_status', 'upp', 'arete', 'campo', 'identificador'];
    const existing: Record<string, unknown> = {};
    for (const k of known) if (res[k] !== undefined && res[k] !== null && res[k] !== '') existing[k] = res[k];
    this.existingAnimal.set(Object.keys(existing).length ? existing : null);
    this.phase.set('blocked');
  }

  ngOnInit() {
    if (this.panelFlow && this.actionType === 'ALTA') {
      if (!this.canUsePanel()) this.blockForbidden();
      else if (!this.hasActiveTenant) this.fail(PANEL_NO_TENANT_MESSAGE);
      else void this.loadPanelUpps();
    }
    if (this.selectedRfid) {
      this.saludForm.patchValue({ rfid_siniiga: this.selectedRfid, livestock_id: this.livestockId });
      this.pesoForm.patchValue({ rfid_siniiga: this.selectedRfid, livestock_id: this.livestockId });
    }
    if (this.actionType === 'COSTOS' && this.livestockId) {
      this.loadAnimalCosts();
    }
    if (this.selectedAnimal && this.actionType === 'EDITAR') {
      this.editForm.patchValue({
        rfid_siniiga: this.selectedAnimal.rfid_siniiga,
        numero_fuego: this.selectedAnimal.numero_fuego ?? '',
        electronic_rfid: this.selectedAnimal.electronic_rfid ?? '',
        business_model: this.selectedAnimal.business_model,
        category: this.selectedAnimal.category,
        current_status: this.selectedAnimal.current_status,
        current_weight_kg: this.selectedAnimal.current_weight_kg,
        birth_date: this.selectedAnimal.birth_date?.split('T')[0] ?? '',
        upp_origen: this.selectedAnimal.upp_origen ?? '',
        tb_test_date: this.selectedAnimal.tb_test_date?.split('T')[0] ?? '',
        br_test_date: this.selectedAnimal.br_test_date?.split('T')[0] ?? ''
      });
    }
  }

  public async submitForm() {
    // The new ALTA flow has its own actions (review / confirm); never fall into the legacy createLivestock.
    if (this.panelFlow && this.actionType === 'ALTA') return;
    if (this.actionType === 'ALTA' && this.altaForm.invalid) return alert('Completa los campos obligatorios./ALTA');
    if (this.actionType === 'SALUD' && this.saludForm.invalid) return alert('Completa los campos obligatorios./SALUD');
    if (this.actionType === 'PESO' && this.pesoForm.invalid) return alert('Completa los campos obligatorios./PESO');
    if (this.actionType === 'EDITAR' && this.editForm.invalid) return alert('Completa los campos obligatorios./EDITAR');

    this.isSaving.set(true);

    try {
      // 2. Enviar a PostgreSQL vía Meta-CRUD
      if (this.actionType === 'ALTA') {
        const payload = this.sanitizeDates(this.altaForm.value);
        await this.cattleApi.createLivestock(payload);
      }
      else if (this.actionType === 'SALUD') {
        const payload = this.saludForm.getRawValue();

        // Empaquetamos la metadata clínica basándonos en el Excel
        const clinicalMetadata = payload.event_type === 'PALPACION' ? {
          resultado: payload.dx_resultado,
          dias_gestacion: payload.dx_resultado === 'PREÑADA' ? payload.dx_dias_gestacion : 0,
          condicion_utero: payload.dx_condicion,
          ovario_afectado: payload.dx_ovario
        } : {};

        await this.cattleApi.createHealthLog({
          livestock_id: payload.livestock_id,
          event_type: payload.event_type,
          event_date: payload.event_date,
          description: payload.description,
          medicines_json: clinicalMetadata // Magia pura: El JSON se guarda en PostgreSQL
        });
      }
      else if (this.actionType === 'PESO') {
        const payload = this.pesoForm.getRawValue();
        await this.cattleApi.createWeightLog({
          livestock_id: payload.livestock_id,
          weight_kg: payload.weight_kg,
          log_date: payload.log_date,
          source_device: 'CAPTURA_MANUAL'
        });
      }
      else if (this.actionType === 'EDITAR') {
        await this.cattleApi.updateLivestock(this.livestockId, this.sanitizeDates(this.editForm.value));
      }
      else if (this.actionType === 'SALIDA') {
        const electronicRfid = this.selectedAnimal?.electronic_rfid;
        if (!electronicRfid) throw new Error('Este animal no tiene RFID electrónico (bolo ruminal) registrado.');

        const resultado = await this.cattleApi.procesarSalidaGanado(electronicRfid);
        if (!resultado.success) {
          alert(`⚠️ Salida rechazada por normativa: ${resultado.motivo}`);
          this.closeModal(false); // No hubo cambios en BD, no hace falta recargar
          return;
        }
      }

      alert('✅ Registro guardado exitosamente en el Ledger.');
      this.closeModal(true); // Emitimos true para que la tabla se recargue

    } catch (error: any) {
      console.error('Error al guardar en PostgreSQL:', error);
      alert(`❌ Ocurrió un error al guardar: ${error.message || 'Error de conexión'}`);
    } finally {
      this.isSaving.set(false);
    }
  }

  public async loadAnimalCosts() {
    this.loadingCosts.set(true);
    try {
      const expenses = await this.cattleApi.getExpensesByAnimal(this.livestockId);
      this.animalExpenses.set(expenses);
    } finally {
      this.loadingCosts.set(false);
    }
  }

  public closeModal(saved: boolean = false) {
    this.close.emit(saved);
  }
}