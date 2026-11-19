import { NgTemplateOutlet } from '@angular/common';
import { ChangeDetectionStrategy, Component, computed, input, signal } from '@angular/core';
import { TableFooterComponent } from '@shared/components/table-footer/table-footer.component';
import { TableToolbarComponent } from '@shared/components/table-toolbar/table-toolbar.component';
import { PagedTable } from '@shared/utils/paged-table.util';
import {
  CampaignEventRow,
  EventSortDir,
  EventSortKey,
  filterEventsByCampaign,
  sortCampaignEventRows,
} from '../../utils/palpation-campaign-compare';
import { COMPARE_NOTE, formatRange } from '../../utils/palpation-campaign-view';
import { Campaign } from '../../utils/palpation-campaigns';
import { resultColorOf } from '../../utils/palpation-colors';
import { HISTORICAL_BADGE, RANCH_BADGE, SUBTYPE_LABEL, UNCONFIRMED_BADGE, formatDate, formatGestation } from '../../utils/palpation-view';
import { PalpationFlagComponent } from '../palpation-flag/palpation-flag.component';
import { PalpationNoteComponent } from '../palpation-note/palpation-note.component';
import { PalpationSwatchComponent } from '../palpation-swatch/palpation-swatch.component';

interface Column {
  readonly key: EventSortKey;
  readonly label: string;
}

export const EVENT_SEARCH_PLACEHOLDER = 'Buscar animal, estado o campaña';
/** The technician is not shown and is not searched. */
export const EVENT_SEARCH_HINT = 'Busca por identificador, categoría, estado del animal, campaña o código sin confirmar.';

/**
 * "Todas las palpaciones": one row per event inside the campaigns, with a Campaña column and a campaign filter. Sortable, searchable and paged with
 * the shared table pieces. There is no technician column and the technician is not searched. An NR is listed and labelled "no cuenta como palpada".
 * Display-only: the rows come from the page and nothing is stored.
 */
@Component({
  selector: 'app-palpation-event-list',
  standalone: true,
  imports: [NgTemplateOutlet, PalpationSwatchComponent, PalpationFlagComponent, PalpationNoteComponent, TableToolbarComponent, TableFooterComponent],
  templateUrl: './palpation-event-list.component.html',
  styles: [
    `
      /* Same width fix as the animals table: the shared toolbar leaves the search field as narrow as its content. */
      :host ::ng-deep app-table-toolbar .input-icon {
        width: 100%;
        max-width: 320px;
      }
      /* The sortable headings are buttons (14px, weight 600, uppercase); the "Detalle" heading has no button, so it gets the same size and weight. */
      .palp-detail-head {
        font-size: 0.875rem;
        font-weight: 600;
        text-transform: uppercase;
      }
    `,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class PalpationEventListComponent {
  /** Every event inside the campaigns, once each (see `campaignEventRows`). */
  readonly rows = input.required<readonly CampaignEventRow[]>();
  readonly campaigns = input.required<readonly Campaign[]>();

  protected readonly sortKey = signal<EventSortKey>('campaign');
  protected readonly sortDir = signal<EventSortDir>('asc');
  private readonly chosenCampaign = signal('TODAS');

  /** The chosen campaign while it still exists; otherwise all of them. */
  protected readonly campaignFilter = computed(() => {
    const id = this.chosenCampaign();
    return id === 'TODAS' || this.campaigns().some(c => c.id === id) ? id : 'TODAS';
  });

  protected readonly visible = computed(() => sortCampaignEventRows(filterEventsByCampaign(this.rows(), this.campaignFilter()), this.sortKey(), this.sortDir()));

  protected readonly columns: readonly Column[] = [
    { key: 'campaign', label: 'Campaña' },
    { key: 'date', label: 'Fecha' },
    { key: 'identifier', label: 'Identificador' },
    { key: 'state', label: 'Resultado' },
    { key: 'gestation', label: 'Gestación' },
    { key: 'currentStatus', label: 'Estado' },
  ];

  protected readonly note = COMPARE_NOTE;
  protected readonly searchPlaceholder = EVENT_SEARCH_PLACEHOLDER;
  protected readonly searchHint = EVENT_SEARCH_HINT;
  protected readonly ranchBadge = RANCH_BADGE;
  protected readonly historicalBadge = HISTORICAL_BADGE;
  protected readonly unconfirmedBadge = UNCONFIRMED_BADGE;
  protected readonly formatDate = formatDate;
  protected readonly formatGestation = formatGestation;
  protected readonly formatRange = formatRange;

  /** The page of the table resets to 1 whenever the rows are recomputed (filter, sort or new data). */
  protected readonly table = new PagedTable<CampaignEventRow>(() => this.visible(), () => this.visible(), {
    // 10, like the other tables: the shared footer shows its first option (10) in the "Mostrar" selector whatever the page size is.
    defaultPageSize: 10,
    search: { fields: r => [r.identifier, r.category, r.currentStatus, r.campaignLabel, r.unconfirmedCode, r.ranchTerm] },
  });

  protected setCampaign(event: Event): void {
    this.chosenCampaign.set((event.target as HTMLSelectElement).value);
  }

  protected sort(key: EventSortKey): void {
    if (this.sortKey() === key) {
      this.sortDir.set(this.sortDir() === 'asc' ? 'desc' : 'asc');
    } else {
      this.sortKey.set(key);
      this.sortDir.set(key === 'date' ? 'desc' : 'asc');
    }
  }

  protected ariaSort(key: EventSortKey): 'ascending' | 'descending' | 'none' {
    if (this.sortKey() !== key) return 'none';
    return this.sortDir() === 'asc' ? 'ascending' : 'descending';
  }

  protected arrow(key: EventSortKey): string {
    if (this.sortKey() !== key) return '';
    return this.sortDir() === 'asc' ? ' ▲' : ' ▼';
  }

  protected resultColor(row: CampaignEventRow): string {
    return resultColorOf({ state: row.state, gestationDays: row.gestation?.days ?? null, subtype: row.subtype, ranchTerm: row.ranchTerm });
  }

  protected subtypeText(row: CampaignEventRow): string | null {
    if (row.subtype === null || row.subtype === 'SIN_CONFIRMAR') return null;
    return SUBTYPE_LABEL[row.subtype];
  }
}
