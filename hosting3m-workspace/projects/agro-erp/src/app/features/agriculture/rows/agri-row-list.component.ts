import { ChangeDetectionStrategy, Component, computed, effect, inject, signal, untracked } from '@angular/core';
import { DatePipe, DecimalPipe } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { toSignal } from '@angular/core/rxjs-interop';
import { map } from 'rxjs';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { TenantService } from 'core-auth';
import {
  AgriRow,
  CENSUS_REASON_OPTIONS,
  CensusHistoryEntry,
  CensusReason,
  HISTORY_REASON_LABELS,
  LotSummary,
  STAGE_OPTIONS,
} from '@core/models/agri.model';
import { AgriApiService } from '../services/agri-api.service';
import { PlantationContextService } from '../services/plantation-context.service';
import { canAdministerPalm, canRecordCensus, todayCdmx, validateCensus, validateRowRange } from '../utils/agri.util';

interface CreateRowsForm { mode: 'single' | 'range'; from: string; to: string; positions: string; }
interface CensusForm { alive: string; positions: string; reason: CensusReason | ''; censusDate: string; notes: string; }

/**
 * Rows of one lot of the ACTIVE plantation. The :lotId param is never trusted: the lot is re-read with a
 * tenant-scoped getone and must belong to the active plantation.
 *  - Rows are created only through agri_bulk_create_rows (single row = from = to): ADMIN / OWNER.
 *  - Counts through agri_record_row_census: ADMIN / OWNER / EDITOR (CUSTOMER read-only).
 *  - Planting positions through the same procedure: ADMIN / OWNER only.
 */
@Component({
  selector: 'app-agri-row-list',
  standalone: true,
  imports: [DatePipe, DecimalPipe, FormsModule, RouterLink],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './agri-row-list.component.html',
})
export class AgriRowListComponent {
  private api = inject(AgriApiService);
  private tenantService = inject(TenantService);
  private route = inject(ActivatedRoute);
  private router = inject(Router);
  context = inject(PlantationContextService);

  private lotId = toSignal(this.route.paramMap.pipe(map(p => p.get('lotId'))));

  canAdminister = computed(() => canAdministerPalm(this.tenantService.activeTenant()?.role));
  canCount = computed(() => canRecordCensus(this.tenantService.activeTenant()?.role));
  readonly reasonOptions = CENSUS_REASON_OPTIONS;
  today = todayCdmx();

  lot = signal<LotSummary | null>(null);
  rows = signal<AgriRow[]>([]);
  isLoading = signal(false);
  loadError = signal<string | null>(null);
  actionError = signal<string | null>(null);
  actionSuccess = signal<string | null>(null);
  possiblyTruncated = signal(false);
  busyId = signal<string | null>(null);
  activeRows = computed(() => this.rows().filter(r => r.isActive));
  nextRowNumber = computed(() => this.activeRows().reduce((max, r) => Math.max(max, r.rowNumber), 0) + 1);

  // Create rows
  createOpen = signal(false);
  createForm = signal<CreateRowsForm>({ mode: 'single', from: '', to: '', positions: '' });
  createSubmitting = signal(false);
  createError = signal<string | null>(null);

  // Census
  censusRow = signal<AgriRow | null>(null);
  censusForm = signal<CensusForm>({ alive: '', positions: '', reason: 'CENSO', censusDate: '', notes: '' });
  censusSubmitting = signal(false);
  censusError = signal<string | null>(null);

  // History
  historyRow = signal<AgriRow | null>(null);
  history = signal<CensusHistoryEntry[]>([]);
  historyLoading = signal(false);
  historyError = signal<string | null>(null);

  constructor() {
    effect(() => {
      const lotId = this.lotId();
      const plantationId = this.context.activePlantationId();
      const status = this.context.status();
      untracked(() => {
        if (status !== 'ready' || !lotId) return;
        if (!plantationId) {
          this.router.navigateByUrl('/agricultura/lotes');
          return;
        }
        void this.load(lotId, plantationId);
      });
    });
  }

  stageLabel(value: string) { return STAGE_OPTIONS.find(s => s.value === value)?.label ?? value; }
  reasonLabel(value: string) { return HISTORY_REASON_LABELS[value as keyof typeof HISTORY_REASON_LABELS] ?? value; }
  /** changed_at is naive UTC: mark it as UTC so the date pipe can show it in CDMX (UTC-6, no DST since 2022). */
  asUtc(value: string): string { return value && !/[zZ]|[+-]\d{2}:?\d{2}$/.test(value) ? `${value}Z` : value; }

  async load(lotId: string, plantationId: string) {
    this.isLoading.set(true);
    this.loadError.set(null);
    try {
      const lot = await this.api.getLotSummary(lotId);
      if (lot.plantationId !== plantationId) {
        // The lot exists in this company but not in the active plantation: never show it under the wrong heading.
        this.router.navigateByUrl('/agricultura/lotes');
        return;
      }
      const rows = await this.api.getRows(lot.id);
      if (this.context.activePlantationId() !== plantationId || this.lotId() !== lotId) return;
      this.lot.set(lot);
      this.rows.set(rows.items);
      this.possiblyTruncated.set(rows.possiblyTruncated);
    } catch (error: any) {
      console.error('[Agro-ERP] Error al cargar las filas:', error);
      this.lot.set(null);
      this.rows.set([]);
      this.loadError.set(error?.message || 'No se pudieron cargar las filas del lote.');
    } finally {
      this.isLoading.set(false);
    }
  }

  private reload() {
    const lot = this.lot();
    const plantationId = this.context.activePlantationId();
    return lot && plantationId ? this.load(lot.id, plantationId) : Promise.resolve();
  }

  // Create rows (single = from = to) ---------------------------------------------------------------

  openCreate(mode: 'single' | 'range') {
    if (!this.canAdminister() || !this.lot()?.isActive) return;
    const next = String(this.nextRowNumber());
    this.createForm.set({ mode, from: next, to: next, positions: '' });
    this.createError.set(null);
    this.actionSuccess.set(null);
    this.createOpen.set(true);
  }

  setCreate<K extends keyof CreateRowsForm>(key: K, value: CreateRowsForm[K]) {
    this.createForm.update(f => ({ ...f, [key]: value }));
  }

  closeCreate() {
    if (!this.createSubmitting()) this.createOpen.set(false);
  }

  async submitCreate() {
    const lot = this.lot();
    if (!lot || !this.canAdminister()) return;
    const f = this.createForm();
    const to = f.mode === 'single' ? f.from : f.to;
    const validation = validateRowRange(f.from, to, f.positions) ?? this.overlap(Number(f.from), Number(to));
    if (validation) {
      this.createError.set(validation);
      return;
    }
    this.createSubmitting.set(true);
    this.createError.set(null);
    try {
      const created = await this.api.createRows(lot.id, Number(f.from), Number(to), Number(f.positions));
      this.createOpen.set(false);
      this.actionSuccess.set(created === 1 ? `Fila ${f.from} registrada.` : `${created} filas registradas (${f.from} a ${to}).`);
      await this.reload();
    } catch (error: any) {
      console.error('[Agro-ERP] Error al registrar filas:', error);
      this.createError.set(error?.message || 'No se pudieron registrar las filas.');
    } finally {
      this.createSubmitting.set(false);
    }
  }

  private overlap(from: number, to: number): string | null {
    const taken = this.activeRows().filter(r => r.rowNumber >= from && r.rowNumber <= to).map(r => r.rowNumber);
    if (!taken.length) return null;
    const sample = taken.slice(0, 10).join(', ') + (taken.length > 10 ? ', …' : '');
    return `Ya existen ${taken.length} fila(s) activa(s) en ese rango (${sample}). No se creó ninguna.`;
  }

  // Census --------------------------------------------------------------------------------------------

  openCensus(row: AgriRow) {
    if (!this.canCount() || !row.isActive) return;
    this.censusRow.set(row);
    this.censusForm.set({ alive: String(row.alivePlants), positions: String(row.plantingPositions), reason: 'CENSO', censusDate: this.today, notes: '' });
    this.censusError.set(null);
    this.actionSuccess.set(null);
  }

  setCensus<K extends keyof CensusForm>(key: K, value: CensusForm[K]) {
    this.censusForm.update(f => ({ ...f, [key]: value }));
  }

  closeCensus() {
    if (!this.censusSubmitting()) this.censusRow.set(null);
  }

  async submitCensus() {
    const row = this.censusRow();
    if (!row || !this.canCount()) return;
    const f = this.censusForm();
    const canChange = this.canAdminister();
    const validation = validateCensus({
      alive: f.alive, positions: f.positions, currentPositions: row.plantingPositions, reason: f.reason,
      censusDate: f.censusDate, today: this.today, canChangePositions: canChange,
    });
    if (validation) {
      this.censusError.set(validation);
      return;
    }
    const positions = f.positions.trim() === '' ? row.plantingPositions : Number(f.positions);
    this.censusSubmitting.set(true);
    this.censusError.set(null);
    try {
      const { changed } = await this.api.recordCensus(row.id, {
        alivePlants: Number(f.alive),
        reason: f.reason as CensusReason,
        censusDate: f.censusDate || null,
        notes: f.notes.trim() || null,
        // Only ADMIN / OWNER send positions; the procedure rejects a change from anyone else anyway.
        plantingPositions: canChange && positions !== row.plantingPositions ? positions : null,
      });
      this.censusRow.set(null);
      this.actionSuccess.set(changed ? `Conteo de la fila ${row.rowNumber} registrado.` : `Conteo de la fila ${row.rowNumber} confirmado sin cambios.`);
      await this.reload();
    } catch (error: any) {
      console.error('[Agro-ERP] Error al registrar el conteo:', error);
      this.censusError.set(error?.message || 'No se pudo registrar el conteo.');
    } finally {
      this.censusSubmitting.set(false);
    }
  }

  // History -------------------------------------------------------------------------------------------

  async openHistory(row: AgriRow) {
    this.historyRow.set(row);
    this.history.set([]);
    this.historyError.set(null);
    this.historyLoading.set(true);
    try {
      const { items } = await this.api.getRowHistory(row.id);
      if (this.historyRow()?.id === row.id) this.history.set(items);
    } catch (error: any) {
      console.error('[Agro-ERP] Error al cargar el historial:', error);
      this.historyError.set(error?.message || 'No se pudo cargar el historial de conteos.');
    } finally {
      this.historyLoading.set(false);
    }
  }

  closeHistory() {
    this.historyRow.set(null);
  }

  // Deactivate / reactivate ------------------------------------------------------------------------------

  async setActive(row: AgriRow, isActive: boolean) {
    if (!this.canAdminister()) return;
    this.actionError.set(null);
    this.actionSuccess.set(null);
    if (isActive && this.activeRows().some(r => r.id !== row.id && r.rowNumber === row.rowNumber)) {
      this.actionError.set(`No se puede reactivar: ya existe otra fila activa con el número ${row.rowNumber}.`);
      return;
    }
    this.busyId.set(row.id);
    try {
      await this.api.setRowActive(row.id, isActive);
      this.actionSuccess.set(isActive ? `Fila ${row.rowNumber} reactivada.` : `Fila ${row.rowNumber} desactivada (su historial se conserva).`);
      await this.reload();
    } catch (error: any) {
      console.error('[Agro-ERP] Error al cambiar el estado de la fila:', error);
      this.actionError.set(error?.message || 'No se pudo cambiar el estado de la fila.');
    } finally {
      this.busyId.set(null);
    }
  }
}
