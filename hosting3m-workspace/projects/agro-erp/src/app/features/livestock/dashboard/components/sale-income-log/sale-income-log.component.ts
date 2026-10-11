import { ChangeDetectionStrategy, Component, computed, effect, inject, input, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { TenantService } from 'core-auth';
import { SaleService } from '@core/services/sale.service';
import { PAYMENT_METHOD_LABEL, SALE_MODE_LABEL, SaleIncome } from '@core/models/sale.model';
import { Livestock } from '../../../models/livestock.model';
import { formatCalendarDate } from '@shared/utils/authorization-deadline.util';
import { formatMoney, summarizeIncome } from '@shared/utils/sale-income.util';

interface IncomeRow {
  income: SaleIncome;
  identifier: string;
  category: string;
}

/**
 * "Ingresos por Venta" tab (migration 071): one row per animal sold through an approved
 * VENTA request. ADMIN-only financial data — mounted by MainDashboardComponent behind the same
 * gate as "Historial de Gastos", and `cattle_sale_income` is ADMIN-only in `crud_models`.
 */
@Component({
  selector: 'app-sale-income-log',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './sale-income-log.component.html',
  changeDetection: ChangeDetectionStrategy.OnPush
})
export class SaleIncomeLogComponent {
  private saleService = inject(SaleService);
  private tenantService = inject(TenantService);

  /** Full herd of the active tenant (sold animals included), used for identifier and category. */
  cattleData = input<Livestock[]>([]);
  /** Herd of the active module (CRIA/ENGORDA/REPRODUCCION), same scope as Cattle Event Log. */
  moduleCattleData = input<Livestock[]>([]);
  /** Bumped by the dashboard on every explicit refresh. */
  refreshToken = input<number>(0);

  readonly saleModeLabel = SALE_MODE_LABEL;
  readonly paymentMethodLabel = PAYMENT_METHOD_LABEL;

  private rawRows = signal<SaleIncome[]>([]);
  public isLoading = signal<boolean>(false);
  public loadError = signal<string | null>(null);
  public dateFrom = signal<string>('');
  public dateTo = signal<string>('');

  private requestSeq = 0;

  constructor() {
    effect(() => {
      const tenantId = this.tenantService.activeTenantId();
      this.refreshToken();
      if (!tenantId) {
        this.rawRows.set([]);
        this.loadError.set('No hay un rancho activo — no se pueden mostrar los ingresos por venta.');
        return;
      }
      this.load();
    });
  }

  /** Latest-wins: an older response that resolves after a newer request is discarded. */
  public async load(): Promise<void> {
    const seq = ++this.requestSeq;
    this.isLoading.set(true);
    this.loadError.set(null);
    try {
      const rows = await this.saleService.getSaleIncome();
      if (seq === this.requestSeq) this.rawRows.set(rows);
    } catch (error: any) {
      if (seq !== this.requestSeq) return;
      // The last good data is kept; only the error is reported (message as-is).
      console.error('[Agro-ERP] Error al cargar ingresos por venta:', error);
      this.loadError.set(error?.message || 'No se pudieron cargar los ingresos por venta.');
    } finally {
      if (seq === this.requestSeq) this.isLoading.set(false);
    }
  }

  /**
   * Second tenant layer: only rows whose own `tenant_id` is the active tenant. Module scope:
   * rows of animals that belong to another module are left out; a row whose animal is not in
   * the herd list at all is kept (with "—"), so income never disappears silently from the totals.
   */
  public rows = computed<IncomeRow[]>(() => {
    const tenantId = Number(this.tenantService.activeTenantId());
    const herd = new Map(this.cattleData().map(a => [a.id, a]));
    const moduleIds = new Set(this.moduleCattleData().map(a => a.id));

    return this.rawRows()
      .filter(r => r.tenantId === tenantId)
      .filter(r => !herd.has(r.livestockId) || moduleIds.has(r.livestockId))
      .map(income => {
        const animal = herd.get(income.livestockId);
        return {
          income,
          identifier: animal?.rfid_siniiga || animal?.numero_fuego || animal?.electronic_rfid || '—',
          category: animal?.category || '—'
        };
      })
      .sort((a, b) => b.income.saleDate.localeCompare(a.income.saleDate));
  });

  /** Inclusive range on `sale_date` (YYYY-MM-DD strings compare chronologically). */
  public filteredRows = computed(() => {
    const from = this.dateFrom();
    const to = this.dateTo();
    return this.rows().filter(r =>
      (!from || r.income.saleDate >= from) && (!to || r.income.saleDate <= to)
    );
  });

  public summary = computed(() => summarizeIncome(this.filteredRows().map(r => r.income)));

  public clearDates(): void {
    this.dateFrom.set('');
    this.dateTo.set('');
  }

  public money(value: number | null): string {
    return formatMoney(value);
  }

  public date(value: string): string {
    return formatCalendarDate(value);
  }
}
