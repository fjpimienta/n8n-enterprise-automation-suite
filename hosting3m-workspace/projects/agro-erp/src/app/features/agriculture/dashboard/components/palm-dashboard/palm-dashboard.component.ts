import { ChangeDetectionStrategy, Component, computed, effect, inject, signal, untracked } from '@angular/core';
import { DecimalPipe } from '@angular/common';
import { RouterLink } from '@angular/router';
import { TenantService } from 'core-auth';
import { LotSummary, PlantationSummary, STAGE_OPTIONS } from '@core/models/agri.model';
import { AgriApiService } from '../../../services/agri-api.service';
import { PlantationContextService } from '../../../services/plantation-context.service';
import { canAdministerPalm } from '../../../utils/agri.util';
import { densityComparison, lotsByStage, plantTotals } from '../../../utils/palm-dashboard.util';

/**
 * Palm dashboard (read-only) for the ACTIVE plantation, from vw_agri_plantation_summary and
 * vw_agri_lot_summary. No financial data in this phase.
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

  constructor() {
    effect(() => {
      const plantationId = this.context.activePlantationId();
      untracked(() => {
        this.summary.set(null);
        this.lots.set([]);
        if (plantationId) void this.load(plantationId);
      });
    });
  }

  stageLabel(value: string) { return STAGE_OPTIONS.find(s => s.value === value)?.label ?? value; }
  stageBadge(value: string) { return STAGE_OPTIONS.find(s => s.value === value)?.badge ?? 'bg-secondary-lt'; }

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
