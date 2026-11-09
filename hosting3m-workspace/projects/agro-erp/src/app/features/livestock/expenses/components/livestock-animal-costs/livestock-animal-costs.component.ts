import { ChangeDetectionStrategy, Component, computed, effect, input, signal, untracked } from '@angular/core';
import { TableFooterComponent } from '@shared/components/table-footer/table-footer.component';
import { TableToolbarComponent } from '@shared/components/table-toolbar/table-toolbar.component';
import { formatMoney } from '@shared/expenses-ui/expenses-ui.util';
import { PagedTable } from '@shared/utils/paged-table.util';
import type { Expense } from '../../../models/expense.model';
import type { Livestock } from '../../../models/livestock.model';
import { AnimalCostRow, AnimalSort, REFERENCE_PRICE_PER_KG, RISK_MARGIN_PCT, animalCosts, sortAnimalCosts, sumAmount } from '../../livestock-expense.util';

/**
 * Accumulated cost per animal (ADMIN only). Pure view over the expenses and herd the dashboard already filtered.
 * "At risk" is also written in text, never only a color.
 */
@Component({
  selector: 'app-livestock-animal-costs',
  standalone: true,
  imports: [TableToolbarComponent, TableFooterComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './livestock-animal-costs.component.html',
})
export class LivestockAnimalCostsComponent {
  canViewAmounts = input<boolean>(false);
  expenses = input<readonly Expense[]>([]);
  /** Resolves animals that are linked to an expense but out of the current herd filter. */
  lookup = input<readonly Livestock[]>([]);
  pricePerKg = input<number>(REFERENCE_PRICE_PER_KG);
  resetKey = input<unknown>(null);
  loading = input<boolean>(false);

  readonly money = formatMoney;
  readonly riskMargin = RISK_MARGIN_PCT;

  sort = signal<AnimalSort>('SPEND');
  onlyRisk = signal(false);

  rows = computed<AnimalCostRow[]>(() => (this.canViewAmounts() ? animalCosts(this.expenses(), this.lookup(), this.pricePerKg()) : []));
  riskCount = computed(() => this.rows().filter(r => r.atRisk).length);
  totalLinked = computed(() => sumAmount(this.expenses().filter(e => !!e.livestock_id)));
  visibleRows = computed(() => {
    const base = this.onlyRisk() ? this.rows().filter(r => r.atRisk) : this.rows();
    return sortAnimalCosts(base, this.sort());
  });

  table = new PagedTable<AnimalCostRow>(
    () => this.visibleRows(),
    () => ({ key: this.resetKey(), sort: this.sort(), risk: this.onlyRisk() }),
    { search: { fields: row => [row.arete, row.fuego, row.category] } },
  );

  constructor() {
    effect(() => {
      this.resetKey();
      untracked(() => { this.sort.set('SPEND'); this.onlyRisk.set(false); this.table.searchQuery.set(''); });
    });
  }

  setSort(mode: AnimalSort) { this.sort.set(mode); }
  toggleRisk() { this.onlyRisk.update(v => !v); }
}
