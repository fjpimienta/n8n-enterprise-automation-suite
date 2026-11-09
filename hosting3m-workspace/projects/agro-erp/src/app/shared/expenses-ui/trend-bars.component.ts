import { ChangeDetectionStrategy, Component, input } from '@angular/core';
import type { TrendBar } from './expenses-ui.util';

/**
 * Plain CSS bar chart. Every bar has a visible text value (rotated labels are avoided: values live in an
 * accessible list below the bars); the period in progress is lighter AND tagged "en curso".
 */
@Component({
  selector: 'exp-trend-bars',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  styleUrl: './expenses-ui.scss',
  styles: `
    .scroll { overflow-x: auto; }
    .bars { display: flex; align-items: flex-end; gap: 4px; height: 140px; min-width: 100%; width: max-content; }
    .col { flex: 1 1 0; min-width: 14px; height: 100%; display: flex; flex-direction: column; justify-content: flex-end; }
    .bar { background: var(--exp-accent); border-radius: 4px 4px 0 0; min-height: 0; }
    .bar.live { opacity: .45; outline: 2px dashed var(--exp-accent); outline-offset: -2px; }
    .labels { display: flex; gap: 4px; width: max-content; min-width: 100%; margin-top: 4px; }
    .labels span { flex: 1 1 0; min-width: 14px; text-align: center; font-size: .7rem; color: var(--exp-muted); }
    details { margin-top: .6rem; font-size: .85rem; }
    summary { cursor: pointer; color: var(--exp-accent-strong); }
    dl { display: grid; grid-template-columns: auto 1fr; gap: .15rem .9rem; margin: .5rem 0 0; }
    dd { margin: 0; text-align: right; }
    .legend { font-size: .75rem; color: var(--exp-muted); margin-top: .4rem; }
  `,
  template: `
    @if (bars().length) {
    <div class="scroll">
      <div class="bars" role="img" [attr.aria-label]="ariaLabel()">
        @for (b of bars(); track b.key) {
        <div class="col" [attr.title]="b.label + ': ' + b.valueText"><div class="bar" [class.live]="b.inProgress" [style.height.%]="b.heightPct"></div></div>
        }
      </div>
      <div class="labels" aria-hidden="true">@for (b of bars(); track b.key) { <span>{{ b.label }}</span> }</div>
    </div>
    <div class="legend">Barra clara con borde punteado = periodo en curso.</div>
    <details open>
      <summary>Valores por periodo</summary>
      <dl>
        @for (b of bars(); track b.key) { <dt>{{ b.label }}{{ b.inProgress ? ' (en curso)' : '' }}</dt><dd>{{ b.valueText }}</dd> }
      </dl>
    </details>
    } @else {
    <div class="exp-state">{{ emptyText() }}</div>
    }
  `,
})
export class TrendBarsComponent {
  bars = input.required<ReadonlyArray<TrendBar>>();
  ariaLabel = input<string>('Gasto por periodo');
  emptyText = input<string>('Sin gastos en el periodo.');
}
