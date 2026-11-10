import { ChangeDetectionStrategy, Component, computed, input } from '@angular/core';
import { formatPercent, sharePercent } from './expenses-ui.util';

export interface ShareItem { key: string; label: string; amount: number; amountText: string; }

/** Rows of label + amount + share % + bar. Percentages are derived from the amounts the caller passes. */
@Component({
  selector: 'exp-share-bar-list',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  styleUrl: './expenses-ui.scss',
  styles: `
    ul { list-style: none; margin: 0; padding: 0; display: grid; gap: .7rem; }
    .exp-head { display: flex; justify-content: space-between; gap: .75rem; font-size: .9rem; color: var(--exp-ink); }
    .exp-name { overflow-wrap: anywhere; }
    .exp-nums { white-space: nowrap; }
    .exp-nums .exp-pct { color: var(--exp-muted); margin-left: .5rem; }
    .exp-track { height: 8px; border-radius: 99px; background: var(--exp-bg); margin-top: .3rem; overflow: hidden; }
    .exp-fill { height: 100%; background: var(--exp-accent); border-radius: 99px; }
  `,
  template: `
    <ul>
      @for (r of rows(); track r.key) {
      <li>
        <div class="exp-head"><span class="exp-name">{{ r.label }}</span><span class="exp-nums"><strong>{{ r.amountText }}</strong><span class="exp-pct">{{ r.pctText }}</span></span></div>
        <div class="exp-track" aria-hidden="true"><div class="exp-fill" [style.width.%]="r.pct"></div></div>
      </li>
      } @empty {
      <li class="exp-state">{{ emptyText() }}</li>
      }
    </ul>
  `,
})
export class ShareBarListComponent {
  items = input.required<ReadonlyArray<ShareItem>>();
  emptyText = input<string>('Sin datos en el periodo.');
  private total = computed(() => this.items().reduce((s, i) => s + i.amount, 0));
  rows = computed(() => this.items().map(i => {
    const pct = sharePercent(i.amount, this.total());
    return { ...i, pct, pctText: formatPercent(pct) };
  }));
}
