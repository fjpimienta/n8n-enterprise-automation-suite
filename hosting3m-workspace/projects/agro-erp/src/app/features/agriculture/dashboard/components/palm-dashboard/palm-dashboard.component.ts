import { ChangeDetectionStrategy, Component, computed, effect, inject, signal, untracked } from '@angular/core';
import { DecimalPipe } from '@angular/common';
import { RouterLink } from '@angular/router';
import { TenantService } from 'core-auth';
import { LotSummary, PlantationSummary, STAGE_OPTIONS } from '@core/models/agri.model';
import { ExpenseBalance } from '@core/models/agri-expense.model';
import { AgriApiService } from '../../../services/agri-api.service';
import { PlantationContextService } from '../../../services/plantation-context.service';
import { canAdministerPalm } from '../../../utils/agri.util';
import { formatMoney, periodLabel } from '../../../utils/expense.util';
import { densityComparison, lotsByStage, plantTotals } from '../../../utils/palm-dashboard.util';

/**
 * Palm dashboard (read-only) for the ACTIVE plantation, from vw_agri_plantation_summary and
 * vw_agri_lot_summary. The only financial figure is the "Gasto del mes" card, for ADMIN / OWNER only, from
 * sp_agri_expense_balance (current month in America/Mexico_City, computed by the database).
 */
@Component({
  selector: 'app-palm-dashboard',
  standalone: true,
  imports: [DecimalPipe, RouterLink],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './palm-dashboard.component.html',
  styleUrls: ['./palm-dashboard.component.scss'],
})
export class PalmDashboardComponent {
  private api = inject(AgriApiService);
  private tenantService = inject(TenantService);
  context = inject(PlantationContextService);

  canAdminister = computed(() => canAdministerPalm(this.tenantService.activeTenant()?.role));
  plantation = this.context.activePlantation;

  summary = signal<PlantationSummary | null>(null);
  lots = signal<LotSummary[]>([]);
  isLoading = signal(false);
  loadError = signal<string | null>(null);
  possiblyTruncated = signal(false);

  activeLots = computed(() => this.lots().filter(l => l.isActive));
  stages = computed(() => lotsByStage(this.lots()));
  totals = computed(() => plantTotals(this.lots()));
  density = computed(() => densityComparison(this.lots()));
  maxStageLots = computed(() => Math.max(1, ...this.stages().map(s => s.lots)));

  readonly money = formatMoney;
  monthBalance = signal<ExpenseBalance | null>(null);
  monthLoading = signal(false);
  monthError = signal<string | null>(null);
  private monthSeq = 0;
  monthLabel = computed(() => {
    const b = this.monthBalance();
    return b ? periodLabel('MONTH', b.dateFrom, b.dateTo) : '';
  });
  /** This plantation's share, as returned by the balance (by_plantation); null = no expenses this month. */
  monthPlantation = computed(() =>
    this.monthBalance()?.byPlantation.find(p => p.plantationId === this.context.activePlantationId()) ?? null);

  constructor() {
    effect(() => {
      const plantationId = this.context.activePlantationId();
      untracked(() => {
        this.summary.set(null);
        this.lots.set([]);
        if (plantationId) void this.load(plantationId);
      });
    });
    // "Gasto del mes": ADMIN / OWNER only; re-evaluated when the company or its role changes.
    effect(() => {
      const tenantId = this.tenantService.activeTenantId();
      const canSee = this.canAdminister();
      untracked(() => {
        this.monthSeq++;
        this.monthBalance.set(null);
        this.monthError.set(null);
        if (tenantId && canSee) void this.loadMonth();
      });
    });
  }

  stageLabel(value: string) { return STAGE_OPTIONS.find(s => s.value === value)?.label ?? value; }
  stageBadge(value: string) { return STAGE_OPTIONS.find(s => s.value === value)?.badge ?? 'bg-secondary-lt'; }

  async loadMonth() {
    const seq = ++this.monthSeq;
    this.monthLoading.set(true);
    try {
      const balance = await this.api.getExpenseBalance();
      if (seq === this.monthSeq) this.monthBalance.set(balance);
    } catch (error: any) {
      if (seq !== this.monthSeq) return;
      // Its own error: the rest of the dashboard stays usable, and an error is never shown as $0.
      console.error('[Agro-ERP] Error al cargar el gasto del mes:', error);
      this.monthError.set(error?.message || 'No se pudo cargar el gasto del mes.');
    } finally {
      if (seq === this.monthSeq) this.monthLoading.set(false);
    }
  }

  async load(plantationId: string) {
    this.isLoading.set(true);
    this.loadError.set(null);
    try {
      const [summaries, lots] = await Promise.all([this.api.getPlantationSummaries(), this.api.getLotSummaries(plantationId)]);
      if (this.context.activePlantationId() !== plantationId) return; // plantation switched meanwhile
      this.summary.set(summaries.items.find(s => s.id === plantationId) ?? null);
      this.lots.set(lots.items);
      this.possiblyTruncated.set(summaries.possiblyTruncated || lots.possiblyTruncated);
    } catch (error: any) {
      // Silent Error Shield: an error is shown as an error, never as "0 lots".
      console.error('[Agro-ERP] Error al cargar el tablero de palma:', error);
      this.loadError.set(error?.message || 'No se pudo cargar el tablero de la plantación.');
    } finally {
      this.isLoading.set(false);
    }
  }
}
