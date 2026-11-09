import { ChangeDetectionStrategy, Component, computed, effect, input, signal, untracked } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { TableFooterComponent } from '@shared/components/table-footer/table-footer.component';
import { CategoryChipsComponent } from '@shared/expenses-ui/category-chips.component';
import { DetailPanelComponent } from '@shared/expenses-ui/detail-panel.component';
import { formatMoney } from '@shared/expenses-ui/expenses-ui.util';
import { PagedTable } from '@shared/utils/paged-table.util';
import type { Expense } from '../../../models/expense.model';
import type { Livestock } from '../../../models/livestock.model';
import { amountOf, categoryChipOptions, categoryLabel, expenseDay, filterHistory } from '../../livestock-expense.util';

/**
 * Expense history (ADMIN only): search, category chips, date range, "only general expenses" and a detail panel.
 * Pure view over the expenses and herd the dashboard already filtered. Expenses are read-only here.
 */
@Component({
  selector: 'app-livestock-expense-history',
  standalone: true,
  imports: [FormsModule, CategoryChipsComponent, DetailPanelComponent, TableFooterComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './livestock-expense-history.component.html',
})
export class LivestockExpenseHistoryComponent {
  canViewAmounts = input<boolean>(false);
  expenses = input<readonly Expense[]>([]);
  /** Herd in the current filter (decides what a general expense is). */
  cattle = input<readonly Livestock[]>([]);
  /** Whole herd, to resolve the animal of an expense that is out of the current filter. */
  lookup = input<readonly Livestock[]>([]);
  resetKey = input<unknown>(null);
  loading = input<boolean>(false);

  readonly money = formatMoney;
  readonly label = categoryLabel;

  search = signal('');
  categoryKey = signal('');
  from = signal('');
  to = signal('');
  onlyGeneral = signal(false);
  selectedId = signal<string | null>(null);

  chips = computed(() => categoryChipOptions(this.expenses()));
  filtered = computed(() => (this.canViewAmounts()
    ? filterHistory(this.expenses(), {
        search: this.search(), categoryKey: this.categoryKey(), from: this.from(), to: this.to(), onlyGeneral: this.onlyGeneral(),
      }, this.lookup(), this.cattle())
    : []));
  selected = computed(() => this.filtered().find(e => e.id === this.selectedId()) ?? null);
  selectedAnimal = computed(() => {
    const id = this.selected()?.livestock_id;
    return id ? this.lookup().find(a => a.id === id) ?? null : null;
  });

  table = new PagedTable<Expense>(
    () => this.filtered(),
    () => ({ key: this.resetKey(), s: this.search(), c: this.categoryKey(), f: this.from(), t: this.to(), g: this.onlyGeneral() }),
  );

  constructor() {
    effect(() => {
      this.resetKey();
      untracked(() => {
        this.search.set(''); this.categoryKey.set(''); this.from.set(''); this.to.set(''); this.onlyGeneral.set(false); this.selectedId.set(null);
      });
    });
  }

  amount(e: Expense) { return amountOf(e); }
  day(e: Expense) { const d = expenseDay(e); return d ? `${d.slice(8, 10)}/${d.slice(5, 7)}/${d.slice(0, 4)}` : '—'; }
  concept(e: Expense) { return e.description?.trim() || 'Sin descripción registrada.'; }
  animalOf(e: Expense) { return e.livestock_id ? this.lookup().find(a => a.id === e.livestock_id) ?? null : null; }
  arete(e: Expense) { return this.animalOf(e)?.rfid_siniiga || e.rfid_siniiga || ''; }
  select(e: Expense) { this.selectedId.set(this.selectedId() === e.id ? null : e.id); }
  toggleGeneral() { this.onlyGeneral.update(v => !v); }
}
