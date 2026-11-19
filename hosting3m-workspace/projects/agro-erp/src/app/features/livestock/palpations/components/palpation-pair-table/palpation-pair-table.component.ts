import { NgTemplateOutlet } from '@angular/common';
import { ChangeDetectionStrategy, Component, input } from '@angular/core';
import { TableFooterComponent } from '@shared/components/table-footer/table-footer.component';
import { TableToolbarComponent } from '@shared/components/table-toolbar/table-toolbar.component';
import { PagedTable } from '@shared/utils/paged-table.util';
import { CompareCategory } from '../../utils/palpation-campaign-compare';
import { PairCell, PairRow } from '../../utils/palpation-campaign-pairs';
import { CATEGORY_COLOR, CATEGORY_LABEL } from '../../utils/palpation-campaign-view';
import { Campaign } from '../../utils/palpation-campaigns';
import { SUBTYPE_LABEL, UNCONFIRMED_BADGE, formatDate } from '../../utils/palpation-view';
import { PalpationFlagComponent } from '../palpation-flag/palpation-flag.component';
import { PalpationSwatchComponent } from '../palpation-swatch/palpation-swatch.component';

export const PAIRS_SEARCH_PLACEHOLDER = 'Buscar animal, estado o código';

/**
 * One list of animals of a pair of campaigns A and B: a table with SINIIGA, quemado, marca, categoría, estado actual and, per campaign, the date, the
 * result, the code as typed, the condition and the unconfirmed-code flag; stacked cards on phones; search and paging with the shared table pieces. It is
 * used by the follow-up groups (persistent and pending) and by the detail of a matrix cell, so the three show animals in exactly the same way.
 * Presentational: it receives the rows, makes no request and stores nothing. The `testid` names the parts (`<testid>-table`, `-row`, `-cards`, `-card`).
 */
@Component({
  selector: 'app-palpation-pair-table',
  standalone: true,
  imports: [NgTemplateOutlet, PalpationSwatchComponent, PalpationFlagComponent, TableToolbarComponent, TableFooterComponent],
  templateUrl: './palpation-pair-table.component.html',
  styles: [
    `
      :host ::ng-deep app-table-toolbar .input-icon {
        width: 100%;
        max-width: 320px;
      }
    `,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class PalpationPairTableComponent {
  readonly rows = input.required<readonly PairRow[]>();
  readonly a = input.required<Campaign>();
  readonly b = input.required<Campaign>();
  readonly testid = input.required<string>();
  /** Accessible description of the table (a screen reader reads it as the caption). */
  readonly caption = input<string>('Animales, con lo que fue cada uno en cada campaña');

  protected readonly searchPlaceholder = PAIRS_SEARCH_PLACEHOLDER;
  protected readonly unconfirmedBadge = UNCONFIRMED_BADGE;
  protected readonly formatDate = formatDate;

  private readonly searchFields = (r: PairRow) => [r.siniiga, r.fuego, r.brand, r.category, r.currentStatus, r.a.rawCode, r.b.rawCode];
  protected readonly table = new PagedTable<PairRow>(() => this.rows(), () => this.rows(), {
    defaultPageSize: 10,
    search: { fields: this.searchFields },
  });

  protected labelOf(category: CompareCategory): string {
    return CATEGORY_LABEL[category];
  }

  protected colorOf(category: CompareCategory): string {
    return CATEGORY_COLOR[category];
  }

  protected conditionText(cell: PairCell): string | null {
    return cell.condition === null ? null : SUBTYPE_LABEL[cell.condition];
  }

  protected identifier(row: PairRow): string {
    return row.siniiga ?? (row.brand && row.fuego ? `${row.brand} ${row.fuego}` : 'Sin identificador');
  }
}
