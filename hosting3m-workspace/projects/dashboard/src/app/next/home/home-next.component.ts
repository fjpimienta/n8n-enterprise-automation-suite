import { ChangeDetectionStrategy, Component, computed, effect, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { CheckinFormComponent } from '@features/booking/components/checkin-form/checkin-form.component';
import { CheckoutFormComponent } from '@features/booking/components/checkout-form/checkout-form.component';
import { RoomDetailModalComponent } from '@features/booking/components/room-detail-modal/room-detail-modal.component';
import { UserFormModalComponent } from '@features/admin/components/user-form-modal/user-form-modal.component';
import { UserListComponent } from '@features/admin/components/user-list/user-list.component';
import { ReservationManagerComponent } from '@features/booking/components/reservation-manager/reservation-manager.component';
import { SkeletonComponent } from '@shared/ui/loader/skeleton/skeleton.component';
import { GuestFormModalComponent } from '@features/admin/components/guest-form-modal/guest-form-modal.component';
import { GuestListComponent } from '@features/admin/components/guest-list/guest-list.component';
import { RoomChecklistModalComponent } from '@features/booking/components/room-checklist-modal/room-checklist-modal.component';
import { ExpenseFormModalComponent } from '@features/finance/components/expense-form-modal/expense-form-modal.component';
import { MaintenanceTicketModalComponent } from '@features/dashboard/components/maintenance-ticket-modal/maintenance-ticket-modal.component';
import { MaintenanceMonitorModalComponent } from '@features/dashboard/components/maintenance-monitor-modal/maintenance-monitor-modal.component';
import { DashboardComponent } from '@features/dashboard/components/dashboard/dashboard.component';
import { DateUtilsService } from '@shared/services/data-utils.service';
import { HIconComponent } from '../../shared/ui/h-icon/h-icon.component';
import { KpiCardComponent } from '../ui/kpi-card.component';
import { RoomCardCompactComponent } from '../ui/room-card-compact.component';
import { FilterOption, RoomFilterBarComponent } from '../ui/room-filter-bar.component';
import { TodayPanelComponent } from '../ui/today-panel.component';
import { MaintenancePanelComponent, MaintenanceRoom } from '../ui/maintenance-panel.component';
import { ShellStateService } from '../shell/shell-state.service';
import { RACK_FILTERS, RackFilter, filterCounts, filterPredicate, groupRooms, matchesQuery, toRoomViews } from '../logic/room-view';
import { computeKpis, kpiText, occupancyHint, occupancyText } from '../logic/kpis';
import { arrivalsToday, departuresToday, validReservations } from '../logic/today';

/**
 * `next` home ("Panel de operación"). Extends the classic page so every flow (check-in, check-out,
 * walk-in, extend stay, report failure, round, expense) keeps using the same handlers; only the
 * presentation of the rack is new. KPIs derive from signals the page already loads.
 */
@Component({
  selector: 'app-home-next',
  standalone: true,
  imports: [CommonModule, FormsModule, CheckinFormComponent, CheckoutFormComponent, RoomDetailModalComponent,
    UserFormModalComponent, UserListComponent, GuestFormModalComponent, GuestListComponent, SkeletonComponent,
    ReservationManagerComponent, RoomChecklistModalComponent, ExpenseFormModalComponent, MaintenanceTicketModalComponent,
    MaintenanceMonitorModalComponent, HIconComponent, KpiCardComponent, RoomCardCompactComponent, RoomFilterBarComponent,
    TodayPanelComponent, MaintenancePanelComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './home-next.component.html'
})
export class HomeNextComponent extends DashboardComponent {
  private readonly shellState = inject(ShellStateService);
  private readonly dates = inject(DateUtilsService);

  readonly rackFilter = signal<RackFilter>('all');
  readonly rackQuery = signal('');
  private readonly collapsed = signal<ReadonlySet<string>>(new Set());

  readonly roomViews = computed(() => toRoomViews(this.bookingService.roomsWithStatus()));
  private readonly reservationRows = computed(() => validReservations(this.adminService.reservations()));
  readonly kpis = computed(() => computeKpis({ rooms: this.roomViews(), reservationsKnown: this.reservationRows().length > 0 }));

  readonly occupancyValue = computed(() => occupancyText(this.kpis()));
  readonly occupancyNote = computed(() => occupancyHint(this.kpis()));
  readonly arrivalsValue = computed(() => kpiText(this.kpis().arrivalsToday));
  readonly departuresValue = computed(() => kpiText(this.kpis().departuresToday));
  readonly toCleanValue = computed(() => kpiText(this.kpis().roomsToClean));
  readonly ticketsValue = computed(() => kpiText(this.kpis().roomsWithOpenTicket));

  readonly filterOptions = computed<FilterOption[]>(() => {
    const rooms = this.roomViews();
    const counts = filterCounts(rooms);
    return RACK_FILTERS.map(f => ({ value: f.value, label: f.label, count: rooms.length === 0 ? null : counts[f.value] }));
  });

  readonly rackGroups = computed(() => {
    const test = filterPredicate(this.rackFilter());
    const query = this.rackQuery();
    return groupRooms(this.roomViews().filter(r => test(r) && matchesQuery(r, query)));
  });

  readonly arrivalItems = computed(() => this.kpis().arrivalsToday === null ? null
    : arrivalsToday(this.roomViews(), this.reservationRows(), this.dates.todayStr));
  readonly departureItems = computed(() => this.kpis().departuresToday === null ? null
    : departuresToday(this.roomViews(), this.reservationRows()));
  readonly maintenanceRooms = computed<MaintenanceRoom[] | null>(() => this.kpis().roomsWithOpenTicket === null ? null
    : this.roomViews().filter(r => r.hasPendingTicket === true).map(r => ({ id: r.id, number: r.room_number })));

  constructor() {
    super();
    // The shell's expense buttons only raise a flag; this page owns the modal.
    effect(() => {
      if (this.shellState.expensePending()) {
        this.shellState.expensePending.set(false);
        this.isExpenseModalOpen.set(true);
      }
    });
  }

  isCollapsed(key: string): boolean { return this.collapsed().has(key); }

  toggleRackGroup(key: string): void {
    const next = new Set(this.collapsed());
    if (!next.delete(key)) next.add(key);
    this.collapsed.set(next);
  }

  clearRackFilters(): void {
    this.rackFilter.set('all');
    this.rackQuery.set('');
  }

  async onRackSelect(roomId: number): Promise<void> {
    const room = this.bookingService.roomsWithStatus().find(r => Number(r.id) === roomId);
    if (room) await this.onSelectRoom(room);
  }

  onRackReport(roomId: number): void {
    const room = this.bookingService.roomsWithStatus().find(r => Number(r.id) === roomId);
    if (room) this.openMaintenanceReport(room);
  }

  onMaintenanceSelect(roomId: number): void {
    this.maintenanceFilterRoomId = roomId;
    this.showMaintenanceMonitor = true;
  }
}
