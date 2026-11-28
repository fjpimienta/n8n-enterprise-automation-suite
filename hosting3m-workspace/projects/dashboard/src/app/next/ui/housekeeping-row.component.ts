import { ChangeDetectionStrategy, Component, computed, input, output } from '@angular/core';
import { HIconComponent } from '../../shared/ui/h-icon/h-icon.component';
import { ChipKind } from '../logic/es-mx';
import { HkGroup, HkItem } from '../logic/housekeeping';
import { StatusChipComponent } from './status-chip.component';

const CHIP: Record<HkGroup, { kind: ChipKind; label: string }> = {
  turnover: { kind: 'occupied', label: 'Ocupada' },
  arrival: { kind: 'cleaning', label: 'Sucia' },
  dirty: { kind: 'cleaning', label: 'Sucia' },
  departure: { kind: 'occupied', label: 'Ocupada' },
  ready: { kind: 'available', label: 'Lista' },
  blocked: { kind: 'maintenance', label: 'Mantenimiento' },
  review: { kind: 'reserved', label: 'Revisar datos' }
};

const NOTE: Record<HkGroup, string> = {
  turnover: 'Sale hoy y llega otro huésped hoy',
  arrival: 'Llega un huésped hoy',
  dirty: '',
  departure: 'Sale hoy',
  ready: '',
  blocked: 'No disponible mientras dure el mantenimiento',
  review: ''
};

function typeText(type: string): string {
  const t = type.trim();
  return t === '' ? '' : t.charAt(0).toUpperCase() + t.slice(1).toLowerCase();
}

/** One housekeeping row. Presentational: the page decides what "Finalizar limpieza" does. */
@Component({
  selector: 'app-housekeeping-row',
  standalone: true,
  imports: [HIconComponent, StatusChipComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="h-hk__info">
      <span class="h-hk__number">{{ item().room.room_number }}</span>
      <span class="h-hk__type">{{ type() }}</span>
      <app-status-chip [kind]="chip().kind" [label]="chip().label" />
      @if (item().needsReview && item().group !== 'review') {
        <app-status-chip kind="reserved" label="Revisar datos" />
      }
      @if (item().room.hasPendingTicket === true && item().group !== 'blocked') {
        <app-status-chip kind="maintenance" label="Falla reportada" />
      }
    </div>
    @if (note()) { <div class="h-hk__note">{{ note() }}</div> }
    @if (item().canFinish) {
      <button type="button" class="h-btn h-btn--primary h-hk__action" [disabled]="busy()" [attr.aria-busy]="busy()"
        [attr.aria-label]="'Finalizar limpieza de la habitación ' + item().room.room_number" (click)="finish.emit(item().room.id)">
        <app-h-icon name="brush" [size]="18" /> {{ busy() ? 'Guardando…' : 'Finalizar limpieza' }}
      </button>
    }`
})
export class HousekeepingRowComponent {
  readonly item = input.required<HkItem>();
  readonly busy = input<boolean>(false);
  readonly finish = output<number>();
  protected readonly chip = computed(() => CHIP[this.item().group]);
  protected readonly type = computed(() => typeText(this.item().room.type));
  protected readonly note = computed(() => NOTE[this.item().group]);
}
