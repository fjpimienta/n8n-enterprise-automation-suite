import { ChangeDetectionStrategy, Component, ElementRef, Injector, OnInit, afterNextRender, computed, inject, signal, viewChild } from '@angular/core';
import { BookingService } from '@features/booking/services/booking.service';
import { MaintenanceService } from '@features/dashboard/services/maintenance.service';
import { AuthService } from 'core-auth';
import { HIconComponent } from '../../shared/ui/h-icon/h-icon.component';
import { formatLongDate } from '../logic/es-mx';
import {
  MT_OLD_RULE_TEXT, buildMaintenanceItems, buildMaintenanceSections, computeMaintenanceCounts, countText, toTicketViews
} from '../logic/maintenance';
import { DENIED_RESOLVE_TEXT, can } from '../logic/permissions';
import { ResolutionPlan, planResolution } from '../logic/resolution';
import { toRoomViews } from '../logic/room-view';
import { KpiCardComponent } from '../ui/kpi-card.component';
import { MaintenanceRowComponent } from '../ui/maintenance-row.component';
import { TicketResolutionService } from './ticket-resolution.service';

interface Feedback { kind: 'ok' | 'error'; text: string }
/** A room whose fault was resolved but whose room update failed: offered once for a retry of that step only. */
interface RoomRetry { roomId: number; number: string }

/**
 * Maintenance board ("Mantenimiento") for the `next` UI. Reads tickets through the existing
 * `MaintenanceService.loadTickets()` and the rooms the app already loads. ONE write flow: resolving a fault (ADMIN
 * only, UI-only gate), through `TicketResolutionService`:
 *  1. re-read the room's tickets (a failed read changes nothing);
 *  2. decide with the pure `planResolution` (last fault sends the room to cleaning; other faults keep it blocked);
 *  3. write the ticket (`status` + `resolved_at`), then, if needed, the room. No optimistic update.
 * The role is checked again here, not only in the template.
 *
 * The service hides `error:true` (it returns an empty list), so "no readable ticket at all" is shown as unknown
 * ("—") and not as zero; a list that holds only resolved tickets is a real "no open tickets".
 */
@Component({
  selector: 'app-maintenance-next',
  standalone: true,
  imports: [HIconComponent, KpiCardComponent, MaintenanceRowComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './maintenance-next.component.html'
})
export class MaintenanceNextComponent implements OnInit {
  private readonly maintenanceService = inject(MaintenanceService);
  private readonly resolution = inject(TicketResolutionService);
  private readonly auth = inject(AuthService);
  private readonly injector = inject(Injector);
  protected readonly bookingService = inject(BookingService);

  protected readonly today = formatLongDate();
  // Read when the template renders (not captured when the component is built).
  protected get oldRule(): string { return MT_OLD_RULE_TEXT; }
  protected get deniedText(): string { return DENIED_RESOLVE_TEXT; }

  private readonly rawTickets = signal<readonly unknown[]>([]);
  protected readonly loading = signal(true);
  protected readonly loadFailed = signal(false);
  protected readonly feedback = signal<Feedback | null>(null);
  protected readonly roomRetry = signal<RoomRetry | null>(null);
  protected readonly pendingId = signal<number | null>(null);
  private readonly feedbackAnchor = viewChild<ElementRef<HTMLElement>>('feedbackAnchor');
  private readonly retryBtn = viewChild<ElementRef<HTMLButtonElement>>('retryBtn');
  /** Bumped on every successful load so ages are computed against the moment of the load. */
  private readonly loadedAt = signal(new Date());

  protected readonly canResolve = computed(() => can(this.auth.currentUser()?.role, 'resolveTicket'));
  private readonly rooms = computed(() => toRoomViews(this.bookingService.roomsWithStatus()));
  private readonly tickets = computed(() => toTicketViews(this.rawTickets()));
  protected readonly ticketsKnown = computed(() => this.tickets().length > 0);
  private readonly items = computed(() => buildMaintenanceItems(this.tickets(), this.rooms(), this.loadedAt()));
  protected readonly sections = computed(() => buildMaintenanceSections(this.items()));
  protected readonly counts = computed(() => computeMaintenanceCounts(this.items(), this.rooms(), this.ticketsKnown()));

  protected readonly open = computed(() => countText(this.counts().open));
  protected readonly critical = computed(() => countText(this.counts().critical));
  protected readonly oldCount = computed(() => countText(this.counts().old));
  protected readonly blockedRooms = computed(() => countText(this.counts().blockedRooms));
  protected readonly pendingRooms = computed(() => countText(this.counts().pendingRooms));
  protected readonly reviewCount = computed(() => this.counts().review ?? 0);

  protected readonly busy = computed(() => this.loading() || this.bookingService.loadingRooms());
  protected readonly empty = computed(() => !this.loading() && !this.loadFailed() && !this.ticketsKnown());
  protected readonly noOpen = computed(() => this.ticketsKnown() && this.sections().length === 0);

  ngOnInit(): void { void this.refresh(); }

  async refresh(keepFeedback = false): Promise<void> {
    if (!keepFeedback) { this.feedback.set(null); this.roomRetry.set(null); }
    this.loading.set(true);
    this.loadFailed.set(false);
    this.bookingService.loadRooms();
    try {
      this.rawTickets.set(await this.maintenanceService.loadTickets(true));
      this.loadedAt.set(new Date());
    } catch {
      this.loadFailed.set(true);
    } finally {
      this.loading.set(false);
    }
  }

  /**
   * The banners sit at the top of the page while the user is working lower down the list, so after every result the
   * page scrolls to them (a sighted user would otherwise see the row vanish and nothing else). When a retry is
   * offered, focus moves to it.
   */
  private revealFeedback(): void {
    afterNextRender(() => {
      const retry = this.retryBtn()?.nativeElement;
      if (retry) { retry.focus(); return; }
      this.feedbackAnchor()?.nativeElement.scrollIntoView?.({ block: 'start', behavior: 'smooth' });
    }, { injector: this.injector });
  }

  isBusy(ticketId: number | null): boolean { return ticketId !== null && this.pendingId() === ticketId; }

  /** The room as the plan needs it, from the rooms already loaded (`null` when it is not in the active list). */
  private roomFor(roomId: number) {
    const r = this.rooms().find(x => x.id === roomId);
    return r ? { number: r.room_number, status: r.status, cleaning_status: r.cleaning_status } : null;
  }

  async resolve(ticketId: number): Promise<void> {
    // Checked here as well as in the template: a hidden button is not a control.
    if (!can(this.auth.currentUser()?.role, 'resolveTicket')) {
      this.feedback.set({ kind: 'error', text: DENIED_RESOLVE_TEXT });
      this.revealFeedback();
      return;
    }
    if (this.pendingId() !== null) return;
    const item = this.items().find(i => i.ticket.id === ticketId);
    if (!item || !item.resolvable || item.ticket.roomId === null) {
      this.feedback.set({ kind: 'error', text: 'Esta falla ya no se puede resolver desde aquí. Actualiza la lista.' });
      this.revealFeedback();
      return;
    }
    const roomId = item.ticket.roomId;
    const roomNumber = this.roomFor(roomId)?.number ?? '';
    this.feedback.set(null);
    this.roomRetry.set(null);
    this.pendingId.set(ticketId);

    let stage: 'verify' | 'ticket' | 'room' = 'verify';
    let plan: ResolutionPlan;
    try {
      const fresh = toTicketViews(await this.resolution.loadRoomTickets(roomId));
      const current = fresh.find(t => t.id === ticketId);
      if (!current || current.status !== 'PENDING') {
        this.feedback.set({ kind: 'error', text: 'Esta falla ya no está pendiente. Se actualizó la lista.' });
        this.revealFeedback();
        await this.refresh(true);
        return;
      }
      plan = planResolution({ tickets: fresh, ticketId, roomId, room: this.roomFor(roomId) });
      stage = 'ticket';
      await this.resolution.resolveTicket(ticketId);
      stage = 'room';
      if (plan.roomWrite) await this.resolution.updateRoom(roomId, plan.roomWrite);
      this.feedback.set({ kind: 'ok', text: plan.message });
    } catch {
      if (stage === 'verify') {
        this.feedback.set({ kind: 'error', text: 'No se pudieron verificar las demás fallas de la habitación. No se hizo ningún cambio.' });
      } else if (stage === 'ticket') {
        this.feedback.set({ kind: 'error', text: 'No se pudo resolver la falla. Sigue pendiente; intenta de nuevo.' });
      } else {
        this.roomRetry.set({ roomId, number: roomNumber });
        this.feedback.set({
          kind: 'error',
          text: `La falla quedó resuelta, pero no se pudo enviar la habitación ${roomNumber} a limpieza. Usa «Reintentar».`
        });
      }
    } finally {
      this.pendingId.set(null);
    }
    this.revealFeedback();
    await this.refresh(true);
  }

  /** Retries ONLY the room step after a partial failure, re-reading the room's tickets first. */
  async retryRoom(): Promise<void> {
    if (!can(this.auth.currentUser()?.role, 'resolveTicket')) {
      this.feedback.set({ kind: 'error', text: DENIED_RESOLVE_TEXT });
      return;
    }
    const retry = this.roomRetry();
    if (!retry || this.pendingId() !== null) return;
    this.pendingId.set(-1);
    try {
      const fresh = toTicketViews(await this.resolution.loadRoomTickets(retry.roomId));
      const plan = planResolution({ tickets: fresh, ticketId: null, roomId: retry.roomId, room: this.roomFor(retry.roomId) });
      if (plan.roomWrite) await this.resolution.updateRoom(retry.roomId, plan.roomWrite);
      this.roomRetry.set(null);
      this.feedback.set({ kind: 'ok', text: plan.message });
    } catch {
      this.feedback.set({ kind: 'error', text: `No se pudo enviar la habitación ${retry.number} a limpieza. Intenta de nuevo.` });
    } finally {
      this.pendingId.set(null);
    }
    this.revealFeedback();
    await this.refresh(true);
  }
}
