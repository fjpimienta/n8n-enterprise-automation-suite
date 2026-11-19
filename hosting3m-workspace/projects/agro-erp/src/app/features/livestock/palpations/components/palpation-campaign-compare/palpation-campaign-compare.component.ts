import { ChangeDetectionStrategy, Component, computed, input, signal } from '@angular/core';
import { TableFooterComponent } from '@shared/components/table-footer/table-footer.component';
import { TableToolbarComponent } from '@shared/components/table-toolbar/table-toolbar.component';
import { PagedTable } from '@shared/utils/paged-table.util';
import { PalpationEventRow, PalpationHerdRow } from '../../models/palpation.types';
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
import { UNCONFIRMED_BADGE } from '../../utils/palpation-view';
import { PalpationSwatchComponent } from '../palpation-swatch/palpation-swatch.component';

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
  imports: [PalpationSwatchComponent, TableToolbarComponent, TableFooterComponent],
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
    `,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class PalpationCampaignCompareComponent {
  readonly events = input.required<readonly PalpationEventRow[]>();
  readonly herd = input.required<readonly PalpationHerdRow[]>();
  /** Valid campaigns, at least 2, oldest first. */
  readonly campaigns = input.required<readonly Campaign[]>();

  protected readonly note = COMPARE_NOTE;
  protected readonly categories = COMPARE_CATEGORIES;
  protected readonly categoryLabel = CATEGORY_LABEL;
  protected readonly categoryColor = CATEGORY_COLOR;
  protected readonly unconfirmedBadge = UNCONFIRMED_BADGE;
  protected readonly formatRange = formatRange;
  protected readonly neverPregnantLabel = neverPregnantLabel;
  protected readonly uninterpretedLabel = uninterpretedLabel;

  private readonly chosenA = signal<string | null>(null);
  private readonly chosenB = signal<string | null>(null);

  /** A and B: the user's choice while it is still one of the campaigns; otherwise the two most recent campaigns. */
  protected readonly a = computed(() => this.pick(this.chosenA(), -2));
  protected readonly b = computed(() => this.pick(this.chosenB(), -1));
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

  private pick(chosen: string | null, fromEnd: number): Campaign | null {
    const list = this.campaigns();
    const byId = list.find(c => c.id === chosen);
    if (byId !== undefined) return byId;
    return list[list.length + fromEnd] ?? null;
  }

  protected setA(event: Event): void {
    this.chosenA.set((event.target as HTMLSelectElement).value);
  }

  protected setB(event: Event): void {
    this.chosenB.set((event.target as HTMLSelectElement).value);
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
