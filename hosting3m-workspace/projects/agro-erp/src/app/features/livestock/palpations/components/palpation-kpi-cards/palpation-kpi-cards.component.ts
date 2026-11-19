import { ChangeDetectionStrategy, Component, computed, input } from '@angular/core';
import { EMPTY_COLOR, FAMILY_COLOR, NO_RESULT_COLOR, RANCH_COLOR, UNINTERPRETED_COLOR } from '../../utils/palpation-colors';
import { PeriodKpis } from '../../utils/palpation-metrics';
import { RANCH_BADGE, SUBTYPE_LABEL, formatDate, formatPercent } from '../../utils/palpation-view';
import { PalpationSwatchComponent } from '../palpation-swatch/palpation-swatch.component';

interface Line {
  readonly label: string;
  readonly count: number;
  /** The colour this category has in the charts. */
  readonly color: string;
  /** Short explanation shown under the line, when the label alone is not enough. */
  readonly hint: string | null;
}

/** Wording of the empty-without-sub-type line and its help: these records have no structured detail (for example the 2023 historical load). */
const NO_SUBTYPE_LABEL = 'Vacía sin detalle de subtipo';
const NO_SUBTYPE_HINT = 'Registros sin detalle estructurado, por ejemplo de la carga histórica';

/**
 * KPI cards of the period. Every figure comes with its absolute number and its denominator: the percentages are over the animals with a
 * clinical result, never over all palpated animals. Ranch terms ("Definido por el rancho"), animals without a result and unrecognised
 * values are shown apart, outside the percentages. If the counts do not add up the cards are not shown (an alert replaces them).
 * Display-only: nothing is stored.
 */
@Component({
  selector: 'app-palpation-kpi-cards',
  standalone: true,
  imports: [PalpationSwatchComponent],
  templateUrl: './palpation-kpi-cards.component.html',
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class PalpationKpiCardsComponent {
  readonly kpis = input.required<PeriodKpis>();
  /** Text of the period, for example "campaña reciente (11/09/2026 a 10/11/2026)". */
  readonly periodLabel = input<string>('el periodo');

  protected readonly ranchBadge = RANCH_BADGE;
  /** Colours of the headings: the same families as the charts. */
  protected readonly color = {
    pregnant: FAMILY_COLOR.pregnant,
    empty: FAMILY_COLOR.empty,
    ranch: FAMILY_COLOR.ranch,
    unconfirmed: EMPTY_COLOR.SIN_CONFIRMAR,
    noResult: NO_RESULT_COLOR,
    uninterpreted: UNINTERPRETED_COLOR,
  } as const;
  protected readonly pctPregnant = computed(() => formatPercent(this.kpis().pctPregnant));
  protected readonly pctEmpty = computed(() => formatPercent(this.kpis().pctEmpty));
  protected readonly lastDate = computed(() => formatDate(this.kpis().lastPalpationDate));

  protected readonly emptyLines = computed<Line[]>(() => {
    const s = this.kpis().emptySubtypes;
    return (Object.keys(s) as (keyof typeof s)[])
      .map(key => ({
        label: key === 'SIN_SUBTIPO' ? NO_SUBTYPE_LABEL : SUBTYPE_LABEL[key],
        count: s[key],
        color: EMPTY_COLOR[key],
        hint: key === 'SIN_SUBTIPO' ? NO_SUBTYPE_HINT : null,
      }))
      .filter(l => l.count > 0);
  });

  protected readonly ranchLines = computed<Line[]>(() => {
    const t = this.kpis().ranchTerms;
    return (Object.keys(t) as (keyof typeof t)[])
      .map(term => ({ label: term, count: t[term], color: RANCH_COLOR[term], hint: null }))
      .filter(l => l.count > 0);
  });
}
