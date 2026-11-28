import { ChangeDetectionStrategy, Component, ElementRef, Injector, OnInit, afterNextRender, computed, inject, signal, viewChild } from '@angular/core';
import { AdminService } from '@features/admin/services/admin.service';
import { BookingService } from '@features/booking/services/booking.service';
import { AuthService } from 'core-auth';
import { HIconComponent } from '../../shared/ui/h-icon/h-icon.component';
import { formatLongDate } from '../logic/es-mx';
import {
  FINISHED_CLEANING, buildHousekeepingItems, buildSections, canFinishCleaning, computeHousekeepingCounts, countText
} from '../logic/housekeeping';
import { DENIED_CLEANING_TEXT, can } from '../logic/permissions';
import { toRoomViews } from '../logic/room-view';
import { validReservations } from '../logic/today';
import { HousekeepingRowComponent } from '../ui/housekeeping-row.component';
import { KpiCardComponent } from '../ui/kpi-card.component';

interface Feedback { kind: 'ok' | 'error'; text: string }

/**
 * Housekeeping board ("Limpieza") for the `next` UI. Reads the rooms and reservations the app already loads
 * (`BookingService` / `AdminService`) and offers ONE write: the existing `BookingService.updateCleaningStatus`
 * (which applies the Silent Error Shield), with the value `clean`. No optimistic update: the list changes only
 * after the service reloads the rooms; a failed write shows an error and leaves everything as it was.
 */
@Component({
  selector: 'app-housekeeping-next',
  standalone: true,
  imports: [HIconComponent, KpiCardComponent, HousekeepingRowComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './housekeeping-next.component.html'
})
export class HousekeepingNextComponent implements OnInit {
  protected readonly bookingService = inject(BookingService);
  private readonly adminService = inject(AdminService);
  private readonly auth = inject(AuthService);
  private readonly injector = inject(Injector);
  private readonly feedbackAnchor = viewChild<ElementRef<HTMLElement>>('feedbackAnchor');

  protected readonly today = formatLongDate();
  protected readonly pending = signal<ReadonlySet<number>>(new Set());
  protected readonly feedback = signal<Feedback | null>(null);

  /** ADMIN and EDITOR may mark a room clean (permissions table); other roles get no action. */
  protected readonly canFinishRole = computed(() => can(this.auth.currentUser()?.role, 'finishCleaning'));
  private readonly rooms = computed(() => toRoomViews(this.bookingService.roomsWithStatus()));
  protected readonly reservationsKnown = computed(() => validReservations(this.adminService.reservations()).length > 0);
  protected readonly loading = computed(() => this.bookingService.loadingRooms() && this.rooms().length === 0);
  protected readonly empty = computed(() => !this.bookingService.loadingRooms() && this.rooms().length === 0);
  protected readonly sections = computed(() => buildSections(buildHousekeepingItems(this.rooms())));
  protected readonly counts = computed(() => computeHousekeepingCounts(this.rooms(), this.reservationsKnown()));

  protected readonly urgent = computed(() => countText(this.counts().urgent));
  protected readonly toClean = computed(() => countText(this.counts().toClean));
  protected readonly departures = computed(() => countText(this.counts().departures));
  protected readonly ready = computed(() => countText(this.counts().ready));
  protected readonly stayOvers = computed(() => countText(this.counts().stayOvers));

  ngOnInit(): void { this.refresh(); }

  refresh(): void {
    this.feedback.set(null);
    this.bookingService.loadRooms();
    this.adminService.loadReservations();
  }

  /** The banners sit at the top of the page while the user works lower down the list: scroll to them after every result. */
  private revealFeedback(): void {
    afterNextRender(() => this.feedbackAnchor()?.nativeElement.scrollIntoView?.({ block: 'start', behavior: 'smooth' }), { injector: this.injector });
  }

  isBusy(roomId: number): boolean { return this.pending().has(roomId); }

  async finish(roomId: number): Promise<void> {
    // Checked here as well as in the template: a hidden button is not a control.
    if (!can(this.auth.currentUser()?.role, 'finishCleaning')) {
      this.feedback.set({ kind: 'error', text: DENIED_CLEANING_TEXT });
      this.revealFeedback();
      return;
    }
    if (this.pending().has(roomId)) return;
    const room = this.rooms().find(r => r.id === roomId);
    // The transition rule lives in the logic layer; the template only offers the button when it holds.
    if (!room || !canFinishCleaning(room)) {
      this.feedback.set({ kind: 'error', text: 'Esta habitación ya no se puede finalizar desde aquí. Actualiza la lista.' });
      this.revealFeedback();
      return;
    }
    this.feedback.set(null);
    this.setPending(roomId, true);
    try {
      await this.bookingService.updateCleaningStatus(roomId, FINISHED_CLEANING);
      this.feedback.set({ kind: 'ok', text: `Habitación ${room.room_number} marcada como limpia.` });
    } catch {
      this.feedback.set({ kind: 'error', text: `No se pudo actualizar la habitación ${room.room_number}. Sigue como estaba; intenta de nuevo.` });
    } finally {
      this.setPending(roomId, false);
    }
    this.revealFeedback();
  }

  private setPending(roomId: number, on: boolean): void {
    const next = new Set(this.pending());
    if (on) next.add(roomId); else next.delete(roomId);
    this.pending.set(next);
  }
}
