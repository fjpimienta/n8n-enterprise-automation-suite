import { ChangeDetectionStrategy, Component, input } from '@angular/core';

export type KpiTone = 'up' | 'down' | 'flat';

/** One headline figure with a label, an optional hint and an optional trend badge (text + arrow, never color alone). */
@Component({
  selector: 'exp-kpi-card',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  styleUrl: './expenses-ui.scss',
  styles: `
    :host { display: block; min-width: 0; }
    .exp-kpi { box-sizing: border-box; background: var(--exp-surface); border: 1px solid var(--exp-border); border-radius: 14px; padding: .9rem 1rem; height: 100%; }
    .exp-kpi-label { font-size: .8rem; color: var(--exp-muted); margin: 0 0 .25rem; }
    .exp-kpi-value { font-size: 1.6rem; font-weight: 700; color: var(--exp-ink); line-height: 1.15; overflow-wrap: anywhere; }
    .exp-kpi-hint { font-size: .8rem; color: var(--exp-muted); margin-top: .25rem; }
    .exp-kpi-delta { display: inline-block; font-size: .8rem; font-weight: 600; margin-top: .35rem; padding: .1rem .5rem; border-radius: 999px; background: var(--exp-bg); color: var(--exp-ink); }
  `,
  template: `
    <div class="exp-kpi">
      <p class="exp-kpi-label">{{ label() }}</p>
      <div class="exp-kpi-value">{{ value() }}</div>
      @if (deltaText()) {
      <span class="exp-kpi-delta" [attr.data-tone]="tone()">{{ tone() === 'up' ? '▲' : tone() === 'down' ? '▼' : '■' }} {{ deltaText() }}</span>
      }
      @if (hint()) { <div class="exp-kpi-hint">{{ hint() }}</div> }
    </div>
  `,
})
export class KpiCardComponent {
  label = input.required<string>();
  value = input.required<string>();
  hint = input<string>('');
  /** Already formatted (e.g. "+12.4%"); empty hides the badge. */
  deltaText = input<string>('');
  tone = input<KpiTone>('flat');
}
