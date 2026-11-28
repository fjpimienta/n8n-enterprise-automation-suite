import { ChangeDetectionStrategy, Component, input, output } from '@angular/core';
import { HIconComponent } from '../../shared/ui/h-icon/h-icon.component';
import { RackFilter } from '../logic/room-view';

/** `count` is null when the rooms are unknown (shown as "—", never as 0). */
export interface FilterOption { value: RackFilter; label: string; count: number | null }

@Component({
  selector: 'app-room-filter-bar',
  standalone: true,
  imports: [HIconComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="h-toolbar">
      <div class="h-search">
        <label class="h-sr-only" for="h-room-search">Buscar habitación</label>
        <app-h-icon name="search" [size]="18" />
        <input id="h-room-search" type="search" placeholder="Buscar habitación…" autocomplete="off"
          [value]="query()" (input)="queryChange.emit($any($event.target).value)" />
      </div>
      <button type="button" class="h-btn" (click)="refresh.emit()"><app-h-icon name="refresh" [size]="18" /> Actualizar</button>
    </div>
    <div class="h-filters" role="group" aria-label="Filtrar habitaciones">
      @for (o of options(); track o.value) {
        <button type="button" class="h-filter" [attr.aria-pressed]="o.value === active()" (click)="filterChange.emit(o.value)">
          {{ o.label }} <span class="h-filter__count">{{ o.count === null ? '—' : o.count }}</span>
        </button>
      }
    </div>`
})
export class RoomFilterBarComponent {
  readonly options = input.required<FilterOption[]>();
  readonly active = input.required<RackFilter>();
  readonly query = input<string>('');
  readonly filterChange = output<RackFilter>();
  readonly queryChange = output<string>();
  readonly refresh = output<void>();
}
