import { ChangeDetectionStrategy, Component, computed, input, model } from '@angular/core';
import { TableFooterComponent } from '@shared/components/table-footer/table-footer.component';
import { TableToolbarComponent } from '@shared/components/table-toolbar/table-toolbar.component';
import { PagedTable } from '@shared/utils/paged-table.util';
import { PalpationEventRow, PalpationHerdRow, ReportStatus } from '../../models/palpation.types';
import {
  COMPARE_CATEGORIES,
  CompareCategory,
  NeverPregnantRow,
  TransitionTable,
  categoryOfCell,
  neverPregnant,
  transitions,
} from '../../utils/palpation-campaign-compare';
import {
  CATEGORY_COLOR,
  CATEGORY_LABEL,
  COMPARE_NOTE,
  formatRange,
  neverPregnantLabel,
  uninterpretedLabel,
} from '../../utils/palpation-campaign-view';
import { Campaign } from '../../utils/palpation-campaigns';
import { MatrixCell, cellIdOf, cellLabel, parseCellId, pickCampaign } from '../../utils/palpation-matrix-cells';
import { UNCONFIRMED_BADGE } from '../../utils/palpation-view';
import { PalpationCampaignPairsComponent } from '../palpation-campaign-pairs/palpation-campaign-pairs.component';
import { PalpationFlagComponent } from '../palpation-flag/palpation-flag.component';
import { PalpationMatrixCellComponent } from '../palpation-matrix-cell/palpation-matrix-cell.component';
import { PalpationNoteComponent } from '../palpation-note/palpation-note.component';
import { PalpationSwatchComponent } from '../palpation-swatch/palpation-swatch.component';

/**
 * What the user chose in the comparison: the ids of campaign A and of campaign B (null = the default, the two most recent campaigns) and the open
 * cell of the matrix (its identifier, such as `sin-registro.prenada`, or null). The page keeps it (two-way binding) so a deep link can set it and the
 * address bar can follow it.
 */
export interface MatrixSelection {
  readonly aId: string | null;
  readonly bId: string | null;
  readonly cell: string | null;
}

interface CellLine {
  readonly label: string;
  readonly text: string;
  readonly color: string;
}

/**
 * Comparison of two campaigns (A to B) and the list of animals with no sign of pregnancy in any campaign. Presentational: the page gives it the
 * valid campaigns (already sorted by start date) and the rows of the report. Every figure is computed for display from those rows and is never
 * stored. It compares results and explains nothing: the note below the title says so and no text names a cause.
 */
@Component({
  selector: 'app-palpation-campaign-compare',
  standalone: true,
  imports: [PalpationSwatchComponent, PalpationFlagComponent, PalpationNoteComponent, PalpationCampaignPairsComponent, PalpationMatrixCellComponent, TableToolbarComponent, TableFooterComponent],
  templateUrl: './palpation-campaign-compare.component.html',
  // Tabler keeps table headings on one line; with 7 columns the transition table would overflow, so its headings may wrap.
  styles: [
    `
      .palp-transition th {
        white-space: normal;
      }
      /* The corner heading ("En Campaña 5 ↓ En Campaña 6 →") reads as one line on desktop; the table is only shown from the md breakpoint up. */
      .palp-transition th.palp-corner {
        white-space: nowrap;
      }
      /* The count of a cell is a button that opens the list of its animals. Own colours: the stock link blue is under 4.5:1 on the dark theme. */
      .palp-cell-btn {
        font-weight: 700;
        text-decoration: underline;
        color: #1a56a0;
      }
      .palp-cell-btn[aria-pressed='true'] {
        background-color: rgba(32, 107, 196, 0.16);
        border-radius: 4px;
        padding: 0 0.35rem !important;
        text-decoration: underline double;
      }
      :host-context([data-bs-theme='dark']) .palp-cell-btn {
        color: #8ab8ee;
      }
      :host-context([data-bs-theme='dark']) .palp-cell-btn[aria-pressed='true'] {
        background-color: rgba(138, 184, 238, 0.2);
      }
    `,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class PalpationCampaignCompareComponent {
  readonly events = input.required<readonly PalpationEventRow[]>();
  readonly herd = input.required<readonly PalpationHerdRow[]>();
  /** Valid campaigns, at least 2, oldest first. */
  readonly campaigns = input.required<readonly Campaign[]>();
  /** Status of the report and the active company, for the guarded CSV export. The defaults refuse it: the page has to say the report is ready. */
  readonly reportStatus = input<ReportStatus>('sin-tenant');
  readonly tenantId = input<number | null>(null);

  protected readonly note = COMPARE_NOTE;
  protected readonly categories = COMPARE_CATEGORIES;
  protected readonly categoryLabel = CATEGORY_LABEL;
  protected readonly categoryColor = CATEGORY_COLOR;
  protected readonly unconfirmedBadge = UNCONFIRMED_BADGE;
  protected readonly formatRange = formatRange;
  protected readonly neverPregnantLabel = neverPregnantLabel;
  protected readonly uninterpretedLabel = uninterpretedLabel;

  /** The choice of A, B and the open cell. Two-way: the page can set it from a deep link and follow it in the address bar. */
  readonly selection = model<MatrixSelection>({ aId: null, bId: null, cell: null });

  /** A and B: the user's choice while it is still one of the campaigns; otherwise the two most recent campaigns. */
  protected readonly a = computed(() => this.pick(this.selection().aId, -2));
  protected readonly b = computed(() => this.pick(this.selection().bId, -1));
  protected readonly sameCampaign = computed(() => this.a() !== null && this.a()?.id === this.b()?.id);

  protected readonly table = computed(() => {
    const a = this.a();
    const b = this.b();
    return a === null || b === null || a.id === b.id ? null : transitions(this.events(), a, b);
  });

  private readonly never = computed(() => neverPregnant(this.events(), this.herd(), this.campaigns()));
  protected readonly mainRows = computed(() => this.never().main);
  protected readonly uninterpretedRows = computed(() => this.never().uninterpreted);

  private readonly searchFields = (r: NeverPregnantRow) => [r.identifier, r.category, r.currentStatus];
  protected readonly mainTable = new PagedTable<NeverPregnantRow>(() => this.mainRows(), () => this.mainRows(), {
    defaultPageSize: 10,
    search: { fields: this.searchFields },
  });
  protected readonly uninterpretedTable = new PagedTable<NeverPregnantRow>(() => this.uninterpretedRows(), () => this.uninterpretedRows(), {
    defaultPageSize: 10,
    search: { fields: this.searchFields },
  });

  /** The open cell, or null. An identifier that is not a known cell (for example from a hand-edited link) is ignored. */
  protected readonly selectedCell = computed<MatrixCell | null>(() => parseCellId(this.selection().cell));
  /** How many animals the matrix counts in the open cell, or null when no cell is open or there is no matrix. */
  protected readonly selectedCount = computed<number | null>(() => {
    const cell = this.selectedCell();
    const t = this.table();
    return cell === null || t === null || !t.identityHolds || t.universe === 0 ? null : t.matrix[cell.from][cell.to];
  });

  /** The button that opened the list, to give the focus back to it when the list is closed. */
  private opener: HTMLElement | null = null;

  private pick(chosen: string | null, fromEnd: number): Campaign | null {
    return pickCampaign(this.campaigns(), chosen, fromEnd);
  }

  protected setA(event: Event): void {
    const aId = (event.target as HTMLSelectElement).value;
    this.selection.update(s => ({ ...s, aId }));
  }

  protected setB(event: Event): void {
    const bId = (event.target as HTMLSelectElement).value;
    this.selection.update(s => ({ ...s, bId }));
  }

  /** Opens the list of the animals of a cell (the button that was pressed is remembered to return the focus to it). */
  protected openCell(from: CompareCategory, to: CompareCategory, event: Event): void {
    this.opener = event.currentTarget instanceof HTMLElement ? event.currentTarget : null;
    this.selection.update(s => ({ ...s, cell: cellIdOf({ from, to }) }));
  }

  protected closeCell(): void {
    this.selection.update(s => ({ ...s, cell: null }));
    if (this.opener?.isConnected) this.opener.focus();
    this.opener = null;
  }

  protected isSelected(from: CompareCategory, to: CompareCategory): boolean {
    const cell = this.selectedCell();
    return cell !== null && cell.from === from && cell.to === to;
  }

  /** Accessible name of a cell button: how many animals and which cell, so a screen reader does not only hear a number. */
  protected cellAria(t: TransitionTable, from: CompareCategory, to: CompareCategory): string {
    const n = t.matrix[from][to];
    return `${n} ${n === 1 ? 'animal' : 'animales'}: ${cellLabel({ from, to }, t.from.label, t.to.label)}. Ver la lista`;
  }

  /** What the animal was in each campaign where it was palpated: one line each, with the colour of its category. */
  protected lines(row: NeverPregnantRow): CellLine[] {
    const lines: CellLine[] = [];
    this.campaigns().forEach((c, i) => {
      const cell = row.cells[i] ?? null;
      if (cell === null) return;
      const category: CompareCategory = categoryOfCell(cell);
      lines.push({ label: c.label, text: CATEGORY_LABEL[category], color: CATEGORY_COLOR[category] });
    });
    return lines;
  }

  /** The campaigns where the animal was not palpated, in one text (a long list of "No palpada" lines would hide the ones that matter). */
  protected missing(row: NeverPregnantRow): string | null {
    const names = this.campaigns().filter((_, i) => (row.cells[i] ?? null) === null).map(c => c.label);
    return names.length === 0 ? null : `No palpada en: ${names.join(', ')}`;
  }

  /** The codes as typed of the events flagged as unconfirmed. Never interpreted. */
  protected codes(row: NeverPregnantRow): string[] {
    const codes = row.cells.flatMap(c => (c !== null && c.unconfirmed && c.event.raw_code ? [c.event.raw_code] : []));
    return [...new Set(codes)];
  }

  protected cell(t: TransitionTable, from: CompareCategory, to: CompareCategory): number {
    return t.matrix[from][to];
  }
}
