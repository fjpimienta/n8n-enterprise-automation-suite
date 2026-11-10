import { ChangeDetectionStrategy, Component, computed, input } from '@angular/core';
import type { TrendBar } from './expenses-ui.util';

/**
 * Plain CSS bar chart. Up to MAX_VALUE_LABELS bars show their value above them; with more, only the largest does
 * (every column keeps a title tooltip). Periods with an amount are also listed in a collapsed details element.
 * The period in progress is lighter AND tagged "en curso".
 */
@Component({
  selector: 'exp-trend-bars',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  styleUrl: './expenses-ui.scss',
  styles: `
    .exp-scroll { overflow-x: auto; }
    .exp-bars { display: flex; align-items: flex-end; gap: 4px; height: 160px; padding-top: 18px; box-sizing: border-box; min-width: 100%; width: max-content; }
    .exp-bars.exp-wide .exp-col { min-width: 52px; }
    .exp-col { position: relative; flex: 1 1 0; min-width: 14px; height: 100%; }
    .exp-bar { position: absolute; left: 0; right: 0; bottom: 0; background: var(--exp-accent); border-radius: 4px 4px 0 0; min-height: 0; }
    .exp-bar.exp-live { opacity: .45; outline: 2px dashed var(--exp-accent); outline-offset: -2px; }
    .exp-val { position: absolute; left: 50%; transform: translateX(-50%); white-space: nowrap; font-size: .68rem; line-height: 1; color: var(--exp-ink); font-family: inherit; font-variant-numeric: tabular-nums; }
    .exp-labels { display: flex; gap: 4px; width: max-content; min-width: 100%; margin-top: 4px; }
    .exp-labels.exp-wide span { min-width: 52px; }
    .exp-labels span { flex: 1 1 0; min-width: 14px; text-align: center; font-size: .7rem; color: var(--exp-muted); }
    details { margin-top: .6rem; font-size: .85rem; }
    summary { cursor: pointer; color: var(--exp-accent-strong); }
    dl { display: grid; grid-template-columns: auto 1fr; gap: .15rem .9rem; margin: .5rem 0 0; }
    dd { margin: 0; text-align: right; }
    .exp-legend { font-size: .75rem; color: var(--exp-muted); margin-top: .4rem; }
  `,
  template: `
    @if (bars().length && !allZero()) {
    <div class="exp-scroll">
      <div class="exp-bars" [class.exp-wide]="showAllValues()" role="img" [attr.aria-label]="ariaLabel()">
        @for (b of bars(); track b.key; let i = $index) {
        <div class="exp-col" [attr.title]="b.label + ': ' + b.valueText">
          <div class="exp-bar" [class.exp-live]="b.inProgress" [style.height.%]="b.heightPct"></div>
          @if (showAllValues() || i === maxIndex()) { <span class="exp-val" [style.bottom]="'calc(' + b.heightPct + '% + 3px)'">{{ b.valueText }}</span> }
        </div>
        }
      </div>
      <div class="exp-labels" [class.exp-wide]="showAllValues()" aria-hidden="true">@for (b of bars(); track b.key) { <span>{{ b.label }}</span> }</div>
    </div>
    @if (hasLive()) { <div class="exp-legend">Barra clara con borde punteado = periodo en curso.</div> }
    @if (listed().length) {
    <details>
      <summary>Valores por periodo</summary>
      <dl>
        @for (b of listed(); track b.key) { <dt>{{ b.label }}{{ b.inProgress ? ' (en curso)' : '' }}</dt><dd>{{ b.valueText }}</dd> }
      </dl>
    </details>
    }
    } @else {
    <div class="exp-state">{{ emptyText() }}</div>
    }
  `,
})
export class TrendBarsComponent {
  bars = input.required<ReadonlyArray<TrendBar>>();
  ariaLabel = input<string>('Gasto por periodo');
  emptyText = input<string>('Sin gastos en el periodo.');

  static readonly MAX_VALUE_LABELS = 12;
  showAllValues = computed(() => this.bars().length <= TrendBarsComponent.MAX_VALUE_LABELS);
  /** Index of the first largest bar (-1 when every bar is zero). */
  maxIndex = computed(() => {
    const bars = this.bars();
    let idx = -1;
    bars.forEach((b, i) => { if (b.value > 0 && (idx < 0 || b.value > bars[idx].value)) idx = i; });
    return idx;
  });
  /** Every period is $0: an empty state replaces the blank chart (and its day axis). */
  allZero = computed(() => this.bars().every(b => !(b.value > 0)));
  hasLive = computed(() => this.bars().some(b => b.inProgress));
  /** Only periods with an amount, in the order received (chronological). */
  listed = computed(() => this.bars().filter(b => b.value > 0));
}
