import { ChangeDetectionStrategy, Component, computed, effect, inject, input, signal, untracked } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { DetailPanelComponent } from '@shared/expenses-ui/detail-panel.component';
import { TenantService } from 'core-auth';
import { Lot } from '@core/models/agri.model';
import { AgriSale, SALE_STATUS_OPTIONS, SaleStatusFilter } from '@core/models/agri-sale.model';
import { formatInstantInCdmx } from '@shared/utils/authorization-deadline.util';
import { AgriApiService } from '../services/agri-api.service';
import { PlantationContextService } from '../services/plantation-context.service';
import { todayCdmx } from '../utils/agri.util';
import { formatMoney, periodLabel, truncToPeriod, validateBalanceRange } from '../utils/expense.util';
import {
  canManageSales,
  emptySalesMessage,
  formatKg,
  formatPricePerKg,
  paymentMethodLabel,
  salePlace,
} from '../utils/sale.util';

/**
 * Registered palm sales (ADMIN only), voided ones included and flagged with their reason. No totals here: they come from
 * the summary (sp_agri_sales_balance). A sale is never edited nor deleted. Same structure as the expense list: stale
 * answers are dropped, an error is never shown as an empty list, and nothing is requested without an active company or
 * for any role but ADMIN.
 */
@Component({
  selector: 'app-sale-list',
  standalone: true,
  imports: [FormsModule, DetailPanelComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './sale-list.component.html',
})
export class SaleListComponent {
  private api = inject(AgriApiService);
  private tenantService = inject(TenantService);
  context = inject(PlantationContextService);

  refreshToken = input<number>(0);

  readonly money = formatMoney;
  readonly kg = formatKg;
  readonly pricePerKg = formatPricePerKg;
  readonly paymentLabel = paymentMethodLabel;
  readonly place = salePlace;
  readonly statusOptions = SALE_STATUS_OPTIONS;

  /** The role of the ACTIVE company, re-checked live (never the JWT role). */
  allowed = computed(() => canManageSales(this.tenantService.activeTenant()?.role));

  dateFrom = signal('');
  dateTo = signal('');
  status = signal<SaleStatusFilter>('ALL');
  plantationId = signal('');
  lotId = signal('');
  lots = signal<Lot[]>([]);
  selectedId = signal<string | null>(null);

  sales = signal<AgriSale[]>([]);
  selected = computed(() => this.sales().find(s => s.id === this.selectedId()) ?? null);
  voidedCount = computed(() => this.sales().filter(s => s.status === 'VOID').length);
  emptyText = computed(() => emptySalesMessage({
    hasStatus: this.status() !== 'ALL', hasPlace: !!this.plantationId(), truncated: this.possiblyTruncated() }));
  isLoading = signal(false);
  loaded = signal(false);
  loadError = signal<string | null>(null);
  filterError = signal<string | null>(null);
  possiblyTruncated = signal(false);
  private seq = 0;
  private lotSeq = 0;

  constructor() {
    // A company or role change clears everything at once (fail-closed) and reloads with the defaults.
    effect(() => {
      const tenantId = this.tenantService.activeTenantId();
      const allowed = this.allowed();
      untracked(() => {
        this.seq++;
        this.resetFilters();
        this.sales.set([]);
        this.possiblyTruncated.set(false);
        this.loaded.set(false);
        this.loadError.set(null);
        this.isLoading.set(false);
        this.selectedId.set(null);
        if (tenantId && allowed) void this.load();
      });
    });
    // A void elsewhere on the screen (or a reload request of the page): reload the applied filters.
    effect(() => {
      this.refreshToken();
      untracked(() => { if (this.loaded()) void this.load(); });
    });
  }

  resetFilters() {
    const today = todayCdmx();
    this.dateFrom.set(truncToPeriod(today, 'MONTH'));
    this.dateTo.set(today);
    this.status.set('ALL');
    this.plantationId.set('');
    this.lotId.set('');
    this.lots.set([]);
    this.filterError.set(null);
  }

  /** "dd/mm/yyyy" from a date-only value (no Date object: no time zone shift). */
  day(date: string) { return periodLabel('DAY', date, date); }

  /**
   * A real instant (created_at / voided_at are timestamptz, so the gateway sends the true instant), in Mexico City time.
   * formatAuthorizationTimestamp is NOT used: it undoes the shift of naive-UTC columns and would show these 6 hours early.
   */
  instant(value: string | null) {
    if (!value) return '—';
    return formatInstantInCdmx(new Date(value));
  }

  select(sale: AgriSale) {
    this.selectedId.set(this.selectedId() === sale.id ? null : sale.id);
  }

  setStatus(value: string) {
    this.status.set(value as SaleStatusFilter);
    void this.load();
  }

  async setPlantation(plantationId: string) {
    this.plantationId.set(plantationId);
    this.lotId.set('');
    const seq = ++this.lotSeq;
    this.lots.set([]);
    if (plantationId) {
      try {
        const { items } = await this.api.getLots(plantationId);
        if (seq === this.lotSeq) this.lots.set(items.sort((a, b) => a.code.localeCompare(b.code, 'es', { numeric: true })));
      } catch (error: any) {
        if (seq !== this.lotSeq) return;
        console.error('[Agro-ERP] Error al cargar los lotes del filtro:', error);
        this.filterError.set(error?.message || 'No se pudieron cargar los lotes de la plantación.');
        return;
      }
    }
    void this.load();
  }

  setLot(lotId: string) {
    this.lotId.set(lotId);
    void this.load();
  }

  async load() {
    // Fail closed: no permission or no active company -> nothing is requested.
    if (!this.allowed()) {
      this.sales.set([]);
      return;
    }
    const error = validateBalanceRange(this.dateFrom(), this.dateTo(), 'MONTH');
    if (error) {
      this.filterError.set(error);
      return;
    }
    this.filterError.set(null);
    const seq = ++this.seq;
    if (!this.tenantService.activeTenantId()) {
      this.sales.set([]);
      this.loadError.set('No hay una empresa activa.');
      return;
    }
    this.isLoading.set(true);
    this.loadError.set(null);
    try {
      const { items, possiblyTruncated } = await this.api.getSales({
        dateFrom: this.dateFrom(), dateTo: this.dateTo(), status: this.status(),
        plantationId: this.plantationId() || null, lotId: this.plantationId() ? this.lotId() || null : null,
      });
      if (seq !== this.seq) return;
      this.sales.set(items);
      this.possiblyTruncated.set(possiblyTruncated);
      this.loaded.set(true);
    } catch (error: any) {
      if (seq !== this.seq) return;
      // Silent Error Shield: an error is never shown as an empty list.
      console.error('[Agro-ERP] Error al cargar las ventas:', error);
      this.sales.set([]);
      this.possiblyTruncated.set(false);
      this.loadError.set(error?.message || 'No se pudieron cargar las ventas.');
    } finally {
      if (seq === this.seq) this.isLoading.set(false);
    }
  }
}
