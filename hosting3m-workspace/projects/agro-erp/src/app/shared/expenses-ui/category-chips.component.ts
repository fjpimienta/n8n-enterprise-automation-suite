import { ChangeDetectionStrategy, Component, input, output } from '@angular/core';
import { ChipOption } from './period-chips.component';

/**
 * Category chips. `allowAll` adds a leading "Todas" chip (filter use, emits ''); without it a chip can be
 * unselected only by choosing another one (capture use). Wraps; never scrolls the page sideways.
 */
@Component({
  selector: 'exp-category-chips',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  styleUrl: './expenses-ui.scss',
  styles: `.group { display: flex; flex-wrap: wrap; gap: .4rem; } .exp-chip.big { min-height: 44px; padding-inline: 1rem; }`,
  template: `
    <div class="group" role="group" [attr.aria-label]="ariaLabel()">
      @if (allowAll()) {
      <button type="button" class="exp-chip" [class.big]="large()" [attr.aria-pressed]="!value()" (click)="valueChange.emit('')">{{ allLabel() }}</button>
      }
      @for (o of options(); track o.value) {
      <button type="button" class="exp-chip" [class.big]="large()" [attr.aria-pressed]="o.value === value()" [disabled]="disabled()" (click)="valueChange.emit(o.value)">{{ o.label }}</button>
      }
    </div>
  `,
})
export class CategoryChipsComponent {
  options = input.required<ReadonlyArray<ChipOption>>();
  value = input<string>('');
  allowAll = input<boolean>(false);
  allLabel = input<string>('Todas');
  large = input<boolean>(false);
  disabled = input<boolean>(false);
  ariaLabel = input<string>('Categoría');
  valueChange = output<string>();
}
