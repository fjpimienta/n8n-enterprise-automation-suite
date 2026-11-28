import { ChangeDetectionStrategy, Component, input } from '@angular/core';
import { HIconComponent, HIconName } from '../../shared/ui/h-icon/h-icon.component';

@Component({
  selector: 'app-kpi-card',
  standalone: true,
  imports: [HIconComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="h-card" role="group" [attr.aria-label]="label() + ': ' + value()">
      <div class="h-kpi__label"><app-h-icon [name]="icon()" [size]="18" /> {{ label() }}</div>
      <div class="h-kpi__value" [attr.aria-busy]="busy()">{{ value() }}</div>
      <div class="h-kpi__hint">{{ hint() }}</div>
    </div>`
})
export class KpiCardComponent {
  readonly label = input.required<string>();
  /** Already formatted text; "—" means unknown. */
  readonly value = input.required<string>();
  readonly hint = input<string>('');
  readonly icon = input.required<HIconName>();
  readonly busy = input<boolean>(false);
}
