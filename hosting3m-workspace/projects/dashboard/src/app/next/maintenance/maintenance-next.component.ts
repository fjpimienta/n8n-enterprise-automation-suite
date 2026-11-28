import { ChangeDetectionStrategy, Component, OnInit, computed, inject, signal } from '@angular/core';
import { BookingService } from '@features/booking/services/booking.service';
import { MaintenanceService } from '@features/dashboard/services/maintenance.service';
import { HIconComponent } from '../../shared/ui/h-icon/h-icon.component';
import { formatLongDate } from '../logic/es-mx';
import {
  MT_OLD_AFTER_DAYS, buildMaintenanceItems, buildMaintenanceSections, computeMaintenanceCounts, countText, toTicketViews
} from '../logic/maintenance';
import { toRoomViews } from '../logic/room-view';
import { KpiCardComponent } from '../ui/kpi-card.component';
import { MaintenanceRowComponent } from '../ui/maintenance-row.component';

/**
 * Maintenance board ("Mantenimiento") for the `next` UI. READ-ONLY: it calls the existing
 * `MaintenanceService.loadTickets()` (the classic monitor uses it too) and reads the rooms the app already loads.
 * No write of any kind. Tickets are resolved from the classic flow until the owner decides option B.
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
  protected readonly bookingService = inject(BookingService);

  protected readonly today = formatLongDate();
  protected readonly oldAfter = MT_OLD_AFTER_DAYS;

  private readonly rawTickets = signal<readonly unknown[]>([]);
  protected readonly loading = signal(true);
  protected readonly loadFailed = signal(false);
  /** Bumped on every successful load so ages are computed against the moment of the load. */
  private readonly loadedAt = signal(new Date());

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

  ngOnInit(): void { this.refresh(); }

  async refresh(): Promise<void> {
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
}
