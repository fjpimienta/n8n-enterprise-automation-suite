import { ChangeDetectionStrategy, Component, input, output } from '@angular/core';
import { HIconComponent, HIconName } from '../../shared/ui/h-icon/h-icon.component';
import { TodayItem } from '../logic/today';

@Component({
  selector: 'app-today-panel',
  standalone: true,
  imports: [HIconComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <section class="h-card" [attr.aria-label]="title()">
      <h2 class="h-section-title"><app-h-icon [name]="icon()" [size]="18" /> {{ title() }}</h2>
      @if (items() === null) {
        <p class="h-empty">Sin datos</p>
      } @else if (items()!.length === 0) {
        <p class="h-empty">{{ emptyText() }}</p>
      } @else {
        <ul class="h-list">
          @for (it of items()!; track it.roomId) {
            <li>
              <button type="button" class="h-filter" (click)="select.emit(it.roomId)" [attr.aria-label]="'Habitación ' + it.roomNumber + ', huésped ' + it.guest">
                <span class="h-list__room">{{ it.roomNumber }}</span>
                <span class="h-list__guest">{{ it.guest }}</span>
              </button>
            </li>
          }
        </ul>
      }
    </section>`
})
export class TodayPanelComponent {
  readonly title = input.required<string>();
  readonly icon = input.required<HIconName>();
  /** `null` = unknown (shown as "Sin datos", never as an empty day). */
  readonly items = input.required<TodayItem[] | null>();
  readonly emptyText = input<string>('Sin movimientos hoy');
  readonly select = output<number>();
}
