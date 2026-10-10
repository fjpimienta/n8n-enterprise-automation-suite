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
  getAuthorizationDeadline,
  formatAuthorizationTimestamp,
  getCountdownSeverity,
  formatCountdown,
  CountdownSeverity
} from '@shared/utils/authorization-deadline.util';
import {
  canCancelRequest,
  isSanitaryExceptionAvailable,
  resolveCurrentUserEmail
} from '@shared/utils/authorization-actions.util';

const TIPO_EVENTO_LABEL: Record<TipoEventoAutorizacion, string> = {
  BAJA_MORTANDAD: 'Baja por Mortandad',
  VENTA: 'Baja por Venta'
};

interface PendingRow {
  row: PendingAuthorization;
  msRemaining: number;
  severity: CountdownSeverity;
  countdownLabel: string;
  canCancel: boolean;
}

type ConfirmAction = DecisionAutorizacion | 'CANCELAR';

interface ConfirmContext {
  row: PendingAuthorization;
  action: ConfirmAction;
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
}

const SUCCESS_MESSAGE: Record<ConfirmAction, string> = {
  APROBADO: '✅ Autorización aprobada correctamente',
  APROBADO_CON_EXCEPCION: '✅ Venta aprobada con excepción sanitaria',
  RECHAZADO: '✅ Autorización rechazada correctamente',
  CANCELAR: '✅ Solicitud cancelada correctamente'
};

@Component({
  selector: 'app-authorization-list',
  standalone: true,
  imports: [CommonModule, ConfirmActionModalComponent],
  templateUrl: './authorization-list.component.html',
  changeDetection: ChangeDetectionStrategy.OnPush
})
export class AuthorizationListComponent {
  private tenantService = inject(TenantService);
  private authService = inject(AuthService);
  public adminService = inject(AdminService);
  private destroyRef = inject(DestroyRef);

  public activeTab = signal<'PENDIENTES' | 'HISTORIAL'>('PENDIENTES');
  public confirmContext = signal<ConfirmContext | null>(null);
  public isSubmitting = signal<boolean>(false);
  public sanitaryExceptionOffer = signal<SanitaryExceptionOffer | null>(null);

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
        this.adminService.loadAuthorizations();
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
        canCancel: canCancelRequest(row, email)
      };
    });
  });

  public historyRows = computed(() => this.adminService.authorizationHistory());

  /** Offer is shown only while its request is still in the current tenant's pending list. */
  public visibleSanitaryExceptionOffer = computed(() => {
    const offer = this.sanitaryExceptionOffer();
    if (!offer) return null;
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

  public openConfirm(row: PendingAuthorization, action: ConfirmAction): void {
    // The sanitary exception only exists for VENTA; never offer it for BAJA_MORTANDAD.
    if (action === 'APROBADO_CON_EXCEPCION' && row.tipo_evento !== 'VENTA') return;
    this.confirmContext.set({ row, action });
  }

  public closeConfirm(): void {
    this.confirmContext.set(null);
  }

  public dismissSanitaryExceptionOffer(): void {
    this.sanitaryExceptionOffer.set(null);
  }

  public async onConfirm(event: { notas?: string }): Promise<void> {
    const ctx = this.confirmContext();
    if (!ctx || this.isSubmitting()) return;

    this.isSubmitting.set(true);
    try {
      const request$ = ctx.action === 'CANCELAR'
        ? this.adminService.cancelAuthorization(ctx.row.id, event.notas ?? '')
        : this.adminService.resolveAuthorization(ctx.row.id, ctx.action, event.notas);

      // The gateway answers HTTP 200 with `error:true` on a Postgres failure (MetaCRUD Silent
      // Error Shield) — the backend message is shown as-is and the row is left untouched.
      const res: any = await lastValueFrom(request$);
      if (res?.error) {
        alert(res.message || 'El servidor reportó un error al procesar la solicitud.');
        return;
      }

      const result = res?.data as ResolveAuthorizationResult | null;
      if (result?.success === false) {
        // A dispatcher rejected the approval (e.g. sanitary rule): the request stays PENDIENTE.
        this.closeConfirm();
        const motivo = result.motivo || 'La aprobación fue rechazada por el servidor.';
        if (ctx.action === 'APROBADO' && isSanitaryExceptionAvailable(ctx.row, result)) {
          this.sanitaryExceptionOffer.set({ row: ctx.row, motivo });
        } else {
          alert(`⚠️ ${motivo}`);
        }
        return;
      }

      if (this.sanitaryExceptionOffer()?.row.id === ctx.row.id) this.sanitaryExceptionOffer.set(null);
      this.adminService.pendingAuthorizations.update(rows => rows.filter(r => r.id !== ctx.row.id));
      alert(SUCCESS_MESSAGE[ctx.action]);
      this.closeConfirm();
      this.refresh();
    } catch (error) {
      console.error('[Agro-ERP] Error al procesar la autorización:', error);
      alert('❌ No se pudo conectar con el servicio de autorizaciones. Intenta de nuevo.');
    } finally {
      this.isSubmitting.set(false);
    }
  }
}
