import { ChangeDetectionStrategy, Component, computed, input, output } from '@angular/core';
import { HIconComponent } from '../../shared/ui/h-icon/h-icon.component';
import { StatusChipComponent } from './status-chip.component';
import { CHIP_LABEL, formatDayMonth } from '../logic/es-mx';
import { RoomView, chipKind } from '../logic/room-view';

@Component({
  selector: 'app-room-card-compact',
  standalone: true,
  imports: [HIconComponent, StatusChipComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  host: { class: 'h-room-host' },
  template: `
    <button type="button" class="h-room" [class]="'h-room h-room--' + kind()" [attr.aria-label]="ariaLabel()" (click)="select.emit(room().id)">
      <span class="h-room__top">
        <span class="h-room__number">{{ room().room_number }}</span>
        <app-status-chip [kind]="kind()" />
      </span>
      @if (room().description) { <span class="h-room__meta">{{ room().description }}</span> }
      <span class="h-room__flags">
        @if (showCleaning()) { <app-status-chip kind="cleaning" /> }
        @if (showArrival()) { <app-status-chip kind="reserved" /> }
        @if (room().hasPendingTicket === true && room().status !== 'maintenance') { <app-status-chip kind="maintenance" label="Falla reportada" /> }
      </span>
      <span class="h-room__foot">{{ dateLine() }}</span>
    </button>
    @if (room().status !== 'maintenance') {
      <button type="button" class="h-room__report" [attr.aria-label]="'Reportar daño en la habitación ' + room().room_number" (click)="report.emit(room().id)">
        <app-h-icon name="tool" [size]="18" />
      </button>
    }`
})
export class RoomCardCompactComponent {
  readonly room = input.required<RoomView>();
  readonly select = output<number>();
  readonly report = output<number>();

  protected readonly kind = computed(() => chipKind(this.room()));
  protected readonly showCleaning = computed(() => this.kind() !== 'cleaning' && this.room().cleaning_status === 'dirty');
  protected readonly showArrival = computed(() => this.kind() !== 'reserved' && this.room().hasIncomingToday && this.room().status === 'available');
  protected readonly dateLine = computed(() => {
    const r = this.room();
    if (!r.displayDate) return '';
    const day = formatDayMonth(r.displayDate);
    if (day === '—') return '';
    return r.status === 'occupied' ? (r.isCheckoutDate ? 'Sale hoy' : `Sale ${day}`) : `Próxima reserva ${day}`;
  });
  protected readonly ariaLabel = computed(() => `Habitación ${this.room().room_number}, ${CHIP_LABEL[this.kind()]}`);
}
