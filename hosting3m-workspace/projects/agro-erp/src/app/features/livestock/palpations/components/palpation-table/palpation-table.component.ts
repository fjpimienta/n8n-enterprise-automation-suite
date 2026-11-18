import { NgTemplateOutlet } from '@angular/common';
import { ChangeDetectionStrategy, Component, input, output } from '@angular/core';
import { TableFooterComponent } from '@shared/components/table-footer/table-footer.component';
import { TableToolbarComponent } from '@shared/components/table-toolbar/table-toolbar.component';
import { PagedTable } from '@shared/utils/paged-table.util';
import { resultColorOf } from '../../utils/palpation-colors';
import { PalpationSwatchComponent } from '../palpation-swatch/palpation-swatch.component';
import {
  HISTORICAL_BADGE,
  PalpationTableRow,
  RANCH_BADGE,
  SUBTYPE_LABEL,
  SortDir,
  SortKey,
  UNCONFIRMED_BADGE,
  formatDate,
  formatGestation,
} from '../../utils/palpation-view';

/** What the table emits when a row's button is pressed: the row, and the button so the drawer can give the focus back to it. */
export interface RowOpenEvent {
  readonly row: PalpationTableRow;
  readonly opener: HTMLElement;
}

interface Column {
  readonly key: SortKey;
  readonly label: string;
}

/**
 * Table of the palpated animals: search and pagination through the shared PagedTable, sortable headers that are real buttons, a button
 * per row, and stacked cards on a phone. The rows arrive filtered and sorted from the page; only search and paging live here.
 * Nothing is persisted.
 */
@Component({
  selector: 'app-palpation-table',
  standalone: true,
  imports: [NgTemplateOutlet, TableToolbarComponent, TableFooterComponent, PalpationSwatchComponent],
  templateUrl: './palpation-table.component.html',
  // In the dark theme the stock outline-primary button is dark blue on near-black (low contrast): lighten text and border there only.
  styles: [
    `
      :host-context([data-bs-theme='dark']) .palp-open {
        color: #8ab8ee;
        border-color: #8ab8ee;
      }
      :host-context([data-bs-theme='dark']) .palp-open:hover {
        color: #ffffff;
        background-color: #206bc4;
        border-color: #206bc4;
      }
    `,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class PalpationTableComponent {
  readonly rows = input.required<readonly PalpationTableRow[]>();
  readonly sortKey = input.required<SortKey>();
  readonly sortDir = input.required<SortDir>();
  readonly sortChange = output<SortKey>();
  readonly rowOpen = output<RowOpenEvent>();

  protected readonly columns: readonly Column[] = [
    { key: 'identifier', label: 'Identificador' },
    { key: 'lastDate', label: 'Última palpación' },
    { key: 'state', label: 'Resultado' },
    { key: 'gestation', label: 'Gestación' },
    { key: 'technician', label: 'Técnico' },
    { key: 'currentStatus', label: 'Estado' },
  ];

  protected readonly ranchBadge = RANCH_BADGE;
  protected readonly historicalBadge = HISTORICAL_BADGE;
  protected readonly unconfirmedBadge = UNCONFIRMED_BADGE;
  protected readonly formatDate = formatDate;
  protected readonly formatGestation = formatGestation;

  /** The page resets to 1 whenever the page recomputes the rows (filters, sort, period). */
  protected readonly table = new PagedTable<PalpationTableRow>(() => this.rows(), () => this.rows(), {
    defaultPageSize: 10,
    search: { fields: r => [r.identifier, r.category, r.currentStatus, r.technician, r.unconfirmedCode] },
  });

  protected ariaSort(key: SortKey): 'ascending' | 'descending' | 'none' {
    if (this.sortKey() !== key) return 'none';
    return this.sortDir() === 'asc' ? 'ascending' : 'descending';
  }

  protected arrow(key: SortKey): string {
    if (this.sortKey() !== key) return '';
    return this.sortDir() === 'asc' ? ' ▲' : ' ▼';
  }

  /** Sub-type of an empty result, from structured data only. An unconfirmed code is shown by its own badge instead. */
  /** Colour of the result of a row: the same function and key as the bars of the chart. */
  protected resultColor(row: PalpationTableRow): string {
    return resultColorOf({ state: row.state, gestationDays: row.gestation?.days ?? null, subtype: row.subtype, ranchTerm: row.ranchTerm });
  }

  protected subtypeText(row: PalpationTableRow): string | null {
    if (row.subtype === null || row.subtype === 'SIN_CONFIRMAR') return null;
    return SUBTYPE_LABEL[row.subtype];
  }

  protected showUnconfirmed(row: PalpationTableRow): boolean {
    return row.unconfirmedCode !== null || row.subtype === 'SIN_CONFIRMAR';
  }

  protected open(event: Event, row: PalpationTableRow): void {
    this.rowOpen.emit({ row, opener: event.currentTarget as HTMLElement });
  }
}
