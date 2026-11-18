import { ChangeDetectionStrategy, Component, computed, input } from '@angular/core';
import { PeriodKpis } from '../../utils/palpation-metrics';
import { RANCH_BADGE, SUBTYPE_LABEL, formatDate, formatPercent } from '../../utils/palpation-view';

interface Line {
  readonly label: string;
  readonly count: number;
}

/**
 * KPI cards of the period. Every figure comes with its absolute number and its denominator: the percentages are over the animals with a
 * clinical result, never over all palpated animals. Ranch terms ("Definido por el rancho"), animals without a result and unrecognised
 * values are shown apart, outside the percentages. If the counts do not add up the cards are not shown (an alert replaces them).
 * Display-only: nothing is stored.
 */
@Component({
  selector: 'app-palpation-kpi-cards',
  standalone: true,
  templateUrl: './palpation-kpi-cards.component.html',
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class PalpationKpiCardsComponent {
  readonly kpis = input.required<PeriodKpis>();
  /** Text of the period, for example "campaña reciente (11/09/2026 a 10/11/2026)". */
  readonly periodLabel = input<string>('el periodo');

  protected readonly ranchBadge = RANCH_BADGE;
  protected readonly pctPregnant = computed(() => formatPercent(this.kpis().pctPregnant));
  protected readonly pctEmpty = computed(() => formatPercent(this.kpis().pctEmpty));
  protected readonly lastDate = computed(() => formatDate(this.kpis().lastPalpationDate));

  protected readonly emptyLines = computed<Line[]>(() => {
    const s = this.kpis().emptySubtypes;
    return (Object.keys(s) as (keyof typeof s)[])
      .map(key => ({ label: SUBTYPE_LABEL[key], count: s[key] }))
      .filter(l => l.count > 0);
  });

  protected readonly ranchLines = computed<Line[]>(() => {
    const t = this.kpis().ranchTerms;
    return (Object.keys(t) as (keyof typeof t)[]).map(term => ({ label: term, count: t[term] })).filter(l => l.count > 0);
  });
}
