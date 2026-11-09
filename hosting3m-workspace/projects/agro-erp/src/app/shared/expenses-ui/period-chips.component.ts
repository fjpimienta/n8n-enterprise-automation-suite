import { ChangeDetectionStrategy, Component, input, output } from '@angular/core';

export interface ChipOption<T extends string = string> { value: T; label: string; }

/** Segmented single-choice chips (period presets). Emits the chosen value. */
@Component({
  selector: 'exp-period-chips',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  styleUrl: './expenses-ui.scss',
  styles: `.group { display: flex; flex-wrap: wrap; gap: .4rem; }`,
  template: `
    <div class="group" role="group" [attr.aria-label]="ariaLabel()">
      @for (o of options(); track o.value) {
      <button type="button" class="exp-chip" [attr.aria-pressed]="o.value === value()" (click)="valueChange.emit(o.value)">{{ o.label }}</button>
      }
    </div>
  `,
})
export class PeriodChipsComponent {
  options = input.required<ReadonlyArray<ChipOption>>();
  value = input<string>('');
  ariaLabel = input<string>('Periodo');
  valueChange = output<string>();
}
