import { Component, DestroyRef, inject, signal, computed, effect, ChangeDetectionStrategy } from '@angular/core';
import { CommonModule } from '@angular/common';
import { lastValueFrom } from 'rxjs';
import { TenantService } from 'core-auth';
import { AdminService } from '@features/admin/services/admin.service';
import { PendingAuthorization, TipoEventoAutorizacion } from '@core/models/pending-authorization.model';
import { ConfirmActionModalComponent } from '@shared/components/confirm-action-modal/confirm-action-modal.component';
import {
  getAuthorizationDeadline,
  getCountdownSeverity,
  formatCountdown,
  CountdownSeverity
} from '@shared/utils/authorization-deadline.util';

const TIPO_EVENTO_LABEL: Record<TipoEventoAutorizacion, string> = {
  BAJA_MORTANDAD: 'Baja por Mortandad',
  VENTA: 'Baja por Venta'
};

interface PendingRow {
  row: PendingAuthorization;
  msRemaining: number;
  severity: CountdownSeverity;
  countdownLabel: string;
}

interface ConfirmContext {
  row: PendingAuthorization;
  decision: 'APROBADO' | 'RECHAZADO';
}

@Component({
  selector: 'app-authorization-list',
  standalone: true,
  imports: [CommonModule, ConfirmActionModalComponent],
  templateUrl: './authorization-list.component.html',
  changeDetection: ChangeDetectionStrategy.OnPush
})
export class AuthorizationListComponent {
  private tenantService = inject(TenantService);
  public adminService = inject(AdminService);
  private destroyRef = inject(DestroyRef);

  public activeTab = signal<'PENDIENTES' | 'HISTORIAL'>('PENDIENTES');
  public confirmContext = signal<ConfirmContext | null>(null);
  public isSubmitting = signal<boolean>(false);

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
    return this.adminService.pendingAuthorizations().map(row => {
      const deadline = getAuthorizationDeadline(row.fecha_solicitud);
      const msRemaining = deadline.getTime() - nowMs;
      return {
        row,
        msRemaining,
        severity: getCountdownSeverity(msRemaining),
        countdownLabel: formatCountdown(msRemaining)
      };
    });
  });

  public historyRows = computed(() => this.adminService.authorizationHistory());

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
      default: return 'bg-secondary-lt';
    }
  }

  public severityBadgeClass(severity: CountdownSeverity): string {
    switch (severity) {
      case 'danger': return 'bg-red-lt';
      case 'warning': return 'bg-yellow-lt';
      default: return 'bg-green-lt';
    }
  }

  public openConfirm(row: PendingAuthorization, decision: 'APROBADO' | 'RECHAZADO'): void {
    this.confirmContext.set({ row, decision });
  }

  public closeConfirm(): void {
    this.confirmContext.set(null);
  }

  public async onConfirm(event: { notas?: string }): Promise<void> {
    const ctx = this.confirmContext();
    if (!ctx) return;

    this.isSubmitting.set(true);
    try {
      // El gateway responde HTTP 200 con `error:true` ante un fallo de Postgres — nunca
      // confiar solo en que la petición HTTP no haya lanzado (MetaCRUD Silent Error Shield).
      const res: any = await lastValueFrom(this.adminService.resolveAuthorization(ctx.row.id, ctx.decision, event.notas));
      if (res && res.error) throw new Error(res.message || 'El servidor reportó un error al resolver la autorización.');

      // Remoción local inmediata de la fila — evita esperar un refetch para reflejar la acción.
      this.adminService.pendingAuthorizations.update(rows => rows.filter(r => r.id !== ctx.row.id));

      alert(ctx.decision === 'APROBADO' ? '✅ Autorización aprobada correctamente' : '✅ Autorización rechazada correctamente');
      this.closeConfirm();
      this.refresh();
    } catch (error) {
      console.error('[Agro-ERP] Error al resolver la autorización:', error);
      alert('❌ No se pudo resolver la autorización. Verifica el detalle en consola.');
    } finally {
      this.isSubmitting.set(false);
    }
  }
}
