import { Component, DestroyRef, inject, signal, computed, effect, ChangeDetectionStrategy } from '@angular/core';
import { CommonModule } from '@angular/common';
import { lastValueFrom } from 'rxjs';
import { AuthService, TenantService } from 'core-auth';
import { AdminService } from '@features/admin/services/admin.service';
import {
  DecisionAutorizacion,
  PendingAuthorization,
  ResolveAuthorizationResult,
  TipoEventoAutorizacion
} from '@core/models/pending-authorization.model';
import { ConfirmActionModalComponent } from '@shared/components/confirm-action-modal/confirm-action-modal.component';
import {
  SaleApprovalItem,
  SaleApprovalModalComponent,
  SaleApprovalSubmit
} from '@features/admin/components/sale-approval-modal/sale-approval-modal.component';
import { SALE_MODE_LABEL, SaleData, SaleMode, SaleReferencePrice } from '@core/models/sale.model';
import { SaleService } from '@core/services/sale.service';
import { formatMoney, parseOptionalNumber, saleDateFor } from '@shared/utils/sale-income.util';
import {
  getAuthorizationDeadline,
  formatAuthorizationTimestamp,
  formatInstantInCdmx,
  getCountdownSeverity,
  formatCountdown,
  isAuthorizationExpired,
  CountdownSeverity
} from '@shared/utils/authorization-deadline.util';
import {
  ActionOutcome,
  canCancelRequest,
  isSanitaryExceptionAvailable,
  isSelectableForBatch,
  modalTransitionFor,
  outcomeForGatewayError,
  resolveCurrentUserEmail
} from '@shared/utils/authorization-actions.util';
import { ToastService } from '@shared/services/toast.service';

const TIPO_EVENTO_LABEL: Record<TipoEventoAutorizacion, string> = {
  BAJA_MORTANDAD: 'Baja por Mortandad',
  VENTA: 'Baja por Venta'
};

interface PendingRow {
  row: PendingAuthorization;
  msRemaining: number;
  severity: CountdownSeverity;
  countdownLabel: string;
  /** Deadline (23:59 America/Mexico_City of the request day) for the badge tooltip. */
  deadlineLabel: string;
  canCancel: boolean;
  /** Deadline passed: the SP rejects any action, so every button is disabled. */
  expired: boolean;
}

type ConfirmAction = DecisionAutorizacion | 'CANCELAR';

interface ConfirmContext {
  row: PendingAuthorization;
  action: ConfirmAction;
  /** VENTA only: the sale data already entered by the ADMIN, re-sent with APROBADO_CON_EXCEPCION. */
  datosVenta?: SaleData;
}

interface ConfirmModalConfig {
  title: string;
  message: string;
  confirmLabel: string;
  cancelLabel: string;
  variant: 'danger' | 'warning' | 'primary';
  notesLabel: string;
  notesRequired: boolean;
}

/** VENTA approval blocked by the sanitary rule, with the exception still available. */
interface SanitaryExceptionOffer {
  row: PendingAuthorization;
  motivo: string;
  datosVenta?: SaleData;
}

interface SaleModalContext {
  variant: 'single' | 'batch';
  items: SaleApprovalItem[];
}

/** Outcome of one `resolver_autorizacion` call, already interpreted. */
type ResolveOutcome =
  | { kind: 'approved'; withException: boolean }
  | { kind: 'pending'; motivo: string; exceptionAvailable: boolean }
  | { kind: 'error'; message: string };

type BatchStatus = 'APROBADA' | 'APROBADA_CON_EXCEPCION' | 'PENDIENTE' | 'ERROR';

interface BatchResult {
  requestId: string;
  identifier: string;
  status: BatchStatus;
  message: string | null;
}

const BATCH_STATUS_LABEL: Record<BatchStatus, string> = {
  APROBADA: 'Aprobada',
  APROBADA_CON_EXCEPCION: 'Aprobada con excepción',
  PENDIENTE: 'Pendiente',
  ERROR: 'Error'
};

const SUCCESS_MESSAGE: Record<ConfirmAction, string> = {
  APROBADO: 'Autorización aprobada',
  APROBADO_CON_EXCEPCION: 'Venta aprobada con excepción sanitaria',
  RECHAZADO: 'Autorización rechazada',
  CANCELAR: 'Solicitud cancelada'
};

const SALE_APPROVED_MESSAGE = 'Venta aprobada';
const NETWORK_ERROR_MESSAGE = 'No se pudo conectar con el servicio de autorizaciones. Intenta de nuevo.';
export const EXPIRED_ACTION_TOOLTIP = 'La solicitud venció; se marcará como EXPIRADO automáticamente';

/**
 * Message of a failed HTTP call: the gateway's `{ error, message }` body when present (e.g. a
 * 403 TENANT_FORBIDDEN), otherwise null so the caller falls back to a connection error.
 */
function httpErrorMessage(error: any): string | null {
  const message = error?.error?.message;
  return typeof message === 'string' && message.trim() ? message : null;
}

@Component({
  selector: 'app-authorization-list',
  standalone: true,
  imports: [CommonModule, ConfirmActionModalComponent, SaleApprovalModalComponent],
  templateUrl: './authorization-list.component.html',
  changeDetection: ChangeDetectionStrategy.OnPush
})
export class AuthorizationListComponent {
  private tenantService = inject(TenantService);
  private authService = inject(AuthService);
  private saleService = inject(SaleService);
  public adminService = inject(AdminService);
  private destroyRef = inject(DestroyRef);
  private toast = inject(ToastService);

  readonly expiredTooltip = EXPIRED_ACTION_TOOLTIP;

  public activeTab = signal<'PENDIENTES' | 'HISTORIAL'>('PENDIENTES');
  public confirmContext = signal<ConfirmContext | null>(null);
  public isSubmitting = signal<boolean>(false);
  /** Backend error of the last attempt in the open modal (confirm or sale form), shown inline. */
  public actionError = signal<string | null>(null);
  public sanitaryExceptionOffer = signal<SanitaryExceptionOffer | null>(null);

  /** Reference prices of the active tenant, used only to pre-fill the sale form. */
  public referencePrices = signal<SaleReferencePrice[]>([]);
  public referencePricesError = signal<string | null>(null);
  public saleModal = signal<SaleModalContext | null>(null);
  private selectedIds = signal<ReadonlySet<string>>(new Set());
  public batchResults = signal<BatchResult[] | null>(null);
  public batchProgress = signal<{ done: number; total: number } | null>(null);

  /** Email of the logged-in user, used only to show "Cancelar solicitud" on own requests. */
  private currentUserEmail = computed(() => resolveCurrentUserEmail(this.authService.currentUser() as any));

  /** Reloj reactivo para que la cuenta regresiva avance sin refrescar la lista. */
  private now = signal<number>(Date.now());

  constructor() {
    const intervalId = setInterval(() => this.now.set(Date.now()), 30_000);
    this.destroyRef.onDestroy(() => clearInterval(intervalId));

    // Re-carga ante cambio de rancho activo — mismo patrón reactivo que MainDashboardComponent.
    effect(() => {
      if (this.tenantService.activeTenantId()) {
        // Nothing prepared for the previous tenant survives a context switch (fail-closed).
        this.saleModal.set(null);
        this.selectedIds.set(new Set());
        this.batchResults.set(null);
        this.adminService.loadAuthorizations();
        this.loadReferencePrices();
      }
    });
  }

  public pendingRows = computed<PendingRow[]>(() => {
    const nowMs = this.now();
    const email = this.currentUserEmail();
    return this.adminService.pendingAuthorizations().map(row => {
      const deadline = getAuthorizationDeadline(row.fecha_solicitud);
      const msRemaining = deadline.getTime() - nowMs;
      return {
        row,
        msRemaining,
        severity: getCountdownSeverity(msRemaining),
        countdownLabel: formatCountdown(msRemaining),
        deadlineLabel: formatInstantInCdmx(deadline),
        canCancel: canCancelRequest(row, email),
        expired: isAuthorizationExpired(row.fecha_solicitud, nowMs)
      };
    });
  });

  public historyRows = computed(() => this.adminService.authorizationHistory());

  /** Offer is shown only while its request is still in the current tenant's pending list. */
  public visibleSanitaryExceptionOffer = computed(() => {
    const offer = this.sanitaryExceptionOffer();
    if (!offer || isAuthorizationExpired(offer.row.fecha_solicitud, this.now())) return null;
    return this.adminService.pendingAuthorizations().some(r => r.id === offer.row.id) ? offer : null;
  });

  public setTab(tab: 'PENDIENTES' | 'HISTORIAL'): void {
    this.activeTab.set(tab);
  }

  public refresh(): void {
    this.adminService.loadAuthorizations();
  }

  /**
   * electronic_rfid || rfid_siniiga || numero_fuego, leído del `payload` JSONB —
   * el snapshot que el solicitante reportó al momento de la solicitud, no el estado
   * actual del animal (que puede haber cambiado desde entonces, p.ej. vía
   * `cattle_identifier_history`).
   */
  public identifierFor(row: PendingAuthorization): string {
    const p = row.payload;
    return p?.electronic_rfid || p?.rfid_siniiga || p?.numero_fuego || 'Sin identificador';
  }

  /** Categoría/especie del animal — sí se lee del join embebido (estado actual). */
  public categorySpeciesFor(row: PendingAuthorization): string {
    const animal = row.cattle_livestock_data;
    return [animal?.category, animal?.species].filter(Boolean).join(' / ') || '—';
  }

  public tipoEventoLabel(tipo: TipoEventoAutorizacion): string {
    return TIPO_EVENTO_LABEL[tipo] ?? tipo;
  }

  public estadoBadgeClass(estado: string): string {
    switch (estado) {
      case 'APROBADO': return 'bg-green-lt';
      case 'RECHAZADO': return 'bg-red-lt';
      case 'EXPIRADO': return 'bg-secondary-lt';
      case 'CANCELADO': return 'bg-dark-lt';
      default: return 'bg-secondary-lt';
    }
  }

  /** fecha_solicitud / fecha_resolucion are UTC; shown in America/Mexico_City. */
  public formatTimestamp(value: string | null | undefined): string {
    return formatAuthorizationTimestamp(value);
  }

  public severityBadgeClass(severity: CountdownSeverity): string {
    switch (severity) {
      case 'danger': return 'bg-red-lt';
      case 'warning': return 'bg-yellow-lt';
      default: return 'bg-green-lt';
    }
  }

  /** Pending, not yet expired VENTA rows of the active tenant: the only rows a batch can take. */
  public selectableSaleRows = computed(() => {
    const nowMs = this.now();
    return this.adminService.pendingAuthorizations().filter(r => isSelectableForBatch(r, nowMs));
  });

  /** Selection pruned against the current pending list (tenant switch, refresh, resolved rows). */
  public selectedSaleRows = computed(() => {
    const ids = this.selectedIds();
    return this.selectableSaleRows().filter(r => ids.has(r.id));
  });

  public allSalesSelected = computed(() => {
    const rows = this.selectableSaleRows();
    return rows.length > 0 && this.selectedSaleRows().length === rows.length;
  });

  /** Transit guides with at least one pending VENTA, for "Seleccionar todos de la guía X". */
  public saleGuides = computed(() => {
    const counts = new Map<string, number>();
    for (const row of this.selectableSaleRows()) {
      const guide = this.guideFor(row);
      if (guide) counts.set(guide, (counts.get(guide) ?? 0) + 1);
    }
    return [...counts.entries()]
      .map(([guide, count]) => ({ guide, count }))
      .sort((a, b) => a.guide.localeCompare(b.guide, 'es', { numeric: true }));
  });

  public isSelected(id: string): boolean {
    return this.selectedIds().has(id);
  }

  public toggleSelected(id: string, checked: boolean): void {
    this.selectedIds.update(ids => {
      const next = new Set(ids);
      if (checked) next.add(id); else next.delete(id);
      return next;
    });
  }

  public toggleAllSales(checked: boolean): void {
    this.selectedIds.set(checked ? new Set(this.selectableSaleRows().map(r => r.id)) : new Set());
  }

  public selectGuide(guide: string): void {
    this.selectedIds.update(ids => {
      const next = new Set(ids);
      for (const row of this.selectableSaleRows()) if (this.guideFor(row) === guide) next.add(row.id);
      return next;
    });
  }

  public clearSelection(): void {
    this.selectedIds.set(new Set());
  }

  public guideFor(row: PendingAuthorization): string | null {
    const guide = row.payload?.guia_transito;
    return typeof guide === 'string' && guide.trim() ? guide.trim() : null;
  }

  /** History tab: amount and mode recorded on approval (`payload.venta`, migration 071). */
  public saleSummaryFor(row: PendingAuthorization): string | null {
    const venta = row.payload?.venta;
    if (row.estado !== 'APROBADO' || row.tipo_evento !== 'VENTA' || !venta) return null;
    const amount = parseOptionalNumber(venta.precio_venta);
    const mode = venta.modo_venta ? SALE_MODE_LABEL[venta.modo_venta as SaleMode] ?? venta.modo_venta : null;
    return [formatMoney(amount), mode].filter(Boolean).join(' · ');
  }

  public batchStatusLabel(status: BatchStatus): string {
    return BATCH_STATUS_LABEL[status];
  }

  public batchStatusClass(status: BatchStatus): string {
    switch (status) {
      case 'APROBADA': return 'bg-green-lt';
      case 'APROBADA_CON_EXCEPCION': return 'bg-yellow-lt';
      case 'PENDIENTE': return 'bg-secondary-lt';
      default: return 'bg-red-lt';
    }
  }

  private referencePricesSeq = 0;

  private async loadReferencePrices(): Promise<void> {
    const seq = ++this.referencePricesSeq;
    this.referencePrices.set([]);
    this.referencePricesError.set(null);
    try {
      const prices = await this.saleService.getReferencePrices();
      if (seq === this.referencePricesSeq) this.referencePrices.set(prices); // latest-wins across tenant switches
    } catch (error: any) {
      if (seq !== this.referencePricesSeq) return;
      // Non-blocking: without reference prices the ADMIN types every amount by hand.
      console.error('[Agro-ERP] Error al cargar precios de referencia:', error);
      this.referencePricesError.set(error?.message || 'No se pudieron cargar los precios de referencia.');
    }
  }

  private saleItemFor(row: PendingAuthorization): SaleApprovalItem {
    return {
      requestId: row.id,
      identifier: this.identifierFor(row),
      category: row.cattle_livestock_data?.category ?? null,
      species: row.cattle_livestock_data?.species ?? null,
      saleDate: saleDateFor(row.payload?.fecha_evento, row.fecha_solicitud),
      guide: this.guideFor(row)
    };
  }

  /** "Aprobar": a VENTA needs the sale form (prices are set only here); a mortality keeps the plain confirm. */
  public approve(row: PendingAuthorization): void {
    if (this.isExpired(row)) return;
    this.actionError.set(null);
    if (row.tipo_evento === 'VENTA') {
      this.saleModal.set({ variant: 'single', items: [this.saleItemFor(row)] });
    } else {
      this.openConfirm(row, 'APROBADO');
    }
  }

  public openBatchApproval(): void {
    const rows = this.selectedSaleRows();
    if (rows.length === 0) return;
    this.actionError.set(null);
    this.saleModal.set({ variant: 'batch', items: rows.map(r => this.saleItemFor(r)) });
  }

  public closeSaleModal(): void {
    if (this.isSubmitting()) return;
    this.actionError.set(null);
    this.saleModal.set(null);
  }

  public isExpired(row: PendingAuthorization): boolean {
    return isAuthorizationExpired(row.fecha_solicitud, this.now());
  }

  public closeBatchResults(): void {
    this.batchResults.set(null);
  }

  public async onSaleApprovalSubmit(submit: SaleApprovalSubmit): Promise<void> {
    const ctx = this.saleModal();
    if (!ctx || this.isSubmitting()) return;
    if (ctx.variant === 'batch') {
      await this.runBatch(submit);
      return;
    }

    const entry = submit.entries[0];
    const row = this.adminService.pendingAuthorizations().find(r => r.id === entry?.requestId);
    if (!entry || !row) return;

    this.isSubmitting.set(true);
    this.actionError.set(null);
    try {
      const result = await this.resolveOne(row.id, 'APROBADO', undefined, entry.data);
      if (result.kind === 'pending') {
        this.saleModal.set(null);
        this.handleBlockedApproval(row, result, entry.data);
        return;
      }
      const outcome: ActionOutcome = result.kind === 'error'
        ? outcomeForGatewayError(result.message)
        : { kind: 'success', message: SALE_APPROVED_MESSAGE };
      this.finishSingleAction(row.id, outcome, () => this.saleModal.set(null));
    } finally {
      this.isSubmitting.set(false);
    }
  }

  /**
   * One call per row, strictly sequential, never stopping on a failed row. A row blocked by the
   * sanitary rule is retried with APROBADO_CON_EXCEPCION (same sale data) only when the ADMIN
   * opted in and wrote the justification.
   */
  private async runBatch(submit: SaleApprovalSubmit): Promise<void> {
    const items = new Map(this.saleModal()?.items.map(i => [i.requestId, i]) ?? []);
    // Only rows still pending for the active tenant are sent (the list may have changed meanwhile).
    const pendingIds = new Set(this.selectableSaleRows().map(r => r.id));
    const entries = submit.entries.filter(e => pendingIds.has(e.requestId));
    const results: BatchResult[] = [];

    this.isSubmitting.set(true);
    this.batchProgress.set({ done: 0, total: entries.length });
    try {
      for (const entry of entries) {
        const identifier = items.get(entry.requestId)?.identifier ?? entry.requestId;
        let outcome = await this.resolveOne(entry.requestId, 'APROBADO', undefined, entry.data);
        let withException = false;

        if (outcome.kind === 'pending' && outcome.exceptionAvailable && submit.exceptionNotes) {
          withException = true;
          outcome = await this.resolveOne(entry.requestId, 'APROBADO_CON_EXCEPCION', submit.exceptionNotes, entry.data);
        }

        if (outcome.kind === 'approved') {
          results.push({
            requestId: entry.requestId, identifier,
            status: withException || outcome.withException ? 'APROBADA_CON_EXCEPCION' : 'APROBADA',
            message: null
          });
          this.adminService.pendingAuthorizations.update(rows => rows.filter(r => r.id !== entry.requestId));
          if (this.sanitaryExceptionOffer()?.row.id === entry.requestId) this.sanitaryExceptionOffer.set(null);
        } else if (outcome.kind === 'pending') {
          results.push({ requestId: entry.requestId, identifier, status: 'PENDIENTE', message: outcome.motivo });
        } else {
          results.push({ requestId: entry.requestId, identifier, status: 'ERROR', message: outcome.message });
        }
        this.batchProgress.set({ done: results.length, total: entries.length });
      }
    } finally {
      this.isSubmitting.set(false);
      this.batchProgress.set(null);
      this.saleModal.set(null);
      this.clearSelection();
      this.batchResults.set(results);
      this.refresh();
    }
  }

  /** Calls the resolver and interprets the MetaCRUD response; never throws. */
  private async resolveOne(
    requestId: string,
    decision: DecisionAutorizacion,
    notas: string | undefined,
    datosVenta: SaleData | undefined
  ): Promise<ResolveOutcome> {
    try {
      const res: any = await lastValueFrom(this.adminService.resolveAuthorization(requestId, decision, notas, datosVenta));
      // HTTP 200 with `error:true` (MetaCRUD Silent Error Shield): the message is shown as-is.
      if (res?.error) return { kind: 'error', message: res.message || 'El servidor reportó un error al procesar la solicitud.' };

      const result = res?.data as ResolveAuthorizationResult | null;
      if (result?.success === false) {
        const row = this.adminService.pendingAuthorizations().find(r => r.id === requestId);
        return {
          kind: 'pending',
          motivo: result.motivo || 'La aprobación fue rechazada por el servidor.',
          exceptionAvailable: decision === 'APROBADO' && !!row && isSanitaryExceptionAvailable(row, result)
        };
      }
      return { kind: 'approved', withException: !!result?.excepcion_sanitaria };
    } catch (error) {
      console.error('[Agro-ERP] Error al procesar la autorización:', error);
      return { kind: 'error', message: httpErrorMessage(error) ?? NETWORK_ERROR_MESSAGE };
    }
  }

  /**
   * Applies `modalTransitionFor`: an error keeps the modal open (typed data kept, message
   * inline); stale (expired / already resolved) and success close it, toast and reload.
   */
  private finishSingleAction(requestId: string, outcome: ActionOutcome, closeModal: () => void): void {
    if (outcome.kind !== 'error' && this.sanitaryExceptionOffer()?.row.id === requestId) {
      this.sanitaryExceptionOffer.set(null);
    }
    if (outcome.kind === 'success') {
      // Immediate local removal; the reload below confirms it.
      this.adminService.pendingAuthorizations.update(rows => rows.filter(r => r.id !== requestId));
    }

    const transition = modalTransitionFor(outcome);
    this.actionError.set(transition.inlineError);
    if (transition.closeModal) closeModal();
    if (transition.toast) this.toast.show(transition.toast.type, transition.toast.text);
    if (transition.reloadList) this.refresh();
  }

  /** success:false from a dispatcher (e.g. sanitary rule): the request stays PENDIENTE. */
  private handleBlockedApproval(
    row: PendingAuthorization,
    result: { motivo: string; exceptionAvailable: boolean },
    datosVenta: SaleData | undefined
  ): void {
    if (result.exceptionAvailable) {
      this.sanitaryExceptionOffer.set({ row, motivo: result.motivo, datosVenta });
    } else {
      this.toast.info(result.motivo);
    }
  }

  public confirmConfig = computed<ConfirmModalConfig | null>(() => {
    const ctx = this.confirmContext();
    if (!ctx) return null;
    const tipo = this.tipoEventoLabel(ctx.row.tipo_evento).toLowerCase();
    switch (ctx.action) {
      case 'APROBADO':
        return {
          title: 'Aprobar autorización',
          message: `¿Confirmas aprobar esta solicitud de ${tipo}? Esta acción es irreversible.`,
          confirmLabel: 'Aprobar',
          cancelLabel: 'Cancelar',
          variant: 'primary',
          notesLabel: 'Notas (opcional)',
          notesRequired: false
        };
      case 'RECHAZADO':
        return {
          title: 'Rechazar autorización',
          message: `¿Confirmas rechazar esta solicitud de ${tipo}? Esta acción es irreversible.`,
          confirmLabel: 'Rechazar',
          cancelLabel: 'Cancelar',
          variant: 'danger',
          notesLabel: 'Motivo del rechazo (obligatorio)',
          notesRequired: true
        };
      case 'APROBADO_CON_EXCEPCION':
        return {
          title: 'Aprobar con excepción sanitaria',
          message: '¿Confirmas aprobar esta venta con excepción sanitaria? La justificación quedará registrada. Esta acción es irreversible.',
          confirmLabel: 'Aprobar con excepción',
          cancelLabel: 'Cancelar',
          variant: 'warning',
          notesLabel: 'Justificación de la excepción (obligatoria)',
          notesRequired: true
        };
      case 'CANCELAR':
        return {
          title: 'Cancelar solicitud',
          message: `¿Confirmas cancelar tu solicitud de ${tipo}? Esta acción es irreversible.`,
          confirmLabel: 'Cancelar solicitud',
          cancelLabel: 'Volver',
          variant: 'danger',
          notesLabel: 'Motivo de la cancelación (obligatorio)',
          notesRequired: true
        };
    }
  });

  public openConfirm(row: PendingAuthorization, action: ConfirmAction, datosVenta?: SaleData): void {
    if (this.isExpired(row)) return;
    this.actionError.set(null);
    // The sanitary exception only exists for VENTA; never offer it for BAJA_MORTANDAD.
    if (action === 'APROBADO_CON_EXCEPCION' && row.tipo_evento !== 'VENTA') return;
    // A plain "Aprobar" of a VENTA without sale data would always fail (P0021): use the sale form.
    if (action === 'APROBADO' && row.tipo_evento === 'VENTA') {
      this.approve(row);
      return;
    }
    this.confirmContext.set({ row, action, datosVenta });
  }

  public closeConfirm(): void {
    if (this.isSubmitting()) return;
    this.actionError.set(null);
    this.confirmContext.set(null);
  }

  public dismissSanitaryExceptionOffer(): void {
    this.sanitaryExceptionOffer.set(null);
  }

  public async onConfirm(event: { notas?: string }): Promise<void> {
    const ctx = this.confirmContext();
    if (!ctx || this.isSubmitting()) return;

    this.isSubmitting.set(true);
    this.actionError.set(null);
    try {
      let outcome: ActionOutcome;
      if (ctx.action === 'CANCELAR') {
        outcome = await this.cancelOne(ctx.row.id, event.notas ?? '');
      } else {
        const result = await this.resolveOne(ctx.row.id, ctx.action, event.notas, ctx.datosVenta);
        if (result.kind === 'pending') {
          this.confirmContext.set(null);
          this.handleBlockedApproval(ctx.row, result, ctx.datosVenta);
          return;
        }
        outcome = result.kind === 'error'
          ? outcomeForGatewayError(result.message)
          : { kind: 'success', message: SUCCESS_MESSAGE[ctx.action] };
      }
      this.finishSingleAction(ctx.row.id, outcome, () => this.confirmContext.set(null));
    } finally {
      this.isSubmitting.set(false);
    }
  }

  /** Calls the cancel SP; `error:true` (HTTP 200) is a failure regardless of the HTTP status. */
  private async cancelOne(requestId: string, motivo: string): Promise<ActionOutcome> {
    try {
      const res: any = await lastValueFrom(this.adminService.cancelAuthorization(requestId, motivo));
      if (res?.error) return outcomeForGatewayError(res.message);
      return { kind: 'success', message: SUCCESS_MESSAGE.CANCELAR };
    } catch (error) {
      console.error('[Agro-ERP] Error al cancelar la solicitud:', error);
      const message = httpErrorMessage(error);
      return message ? outcomeForGatewayError(message) : { kind: 'error', message: NETWORK_ERROR_MESSAGE };
    }
  }
}
