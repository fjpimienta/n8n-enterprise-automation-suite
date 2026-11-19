import { ChangeDetectionStrategy, Component, input } from '@angular/core';

/**
 * A small round colour sample that goes next to a name. It repeats the colour of the chart for that category in cards, tables and the drawer.
 * Decoration only (`aria-hidden`): the name and the number next to it always say the same thing, so colour is never the only signal.
 */
@Component({
  selector: 'app-palp-swatch',
  standalone: true,
  template: '<span class="palp-swatch" aria-hidden="true" [style.background-color]="color()"></span>',
  styles: [
    `
      .palp-swatch {
        display: inline-block;
        width: 0.75em;
        height: 0.75em;
        margin-right: 0.4em;
        border-radius: 50%;
        vertical-align: -0.05em;
        box-shadow: 0 0 0 1px rgba(128, 138, 152, 0.65);
      }
    `,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class PalpationSwatchComponent {
  readonly color = input.required<string>();
}
