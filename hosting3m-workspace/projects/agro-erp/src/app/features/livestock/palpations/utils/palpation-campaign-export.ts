import { InjectionToken } from '@angular/core';
import { CsvColumn, exportRowsToCsv } from '@shared/utils/csv-export.util';
import { PalpationEventRow, PalpationHerdRow, ReportStatus } from '../models/palpation.types';
import { CATEGORY_LABEL, GROUP_LABEL } from './palpation-campaign-view';
import { PairRow, pairLists } from './palpation-campaign-pairs';
import { Campaign, validateCampaigns } from './palpation-campaigns';
import { SUBTYPE_LABEL } from './palpation-view';

/**
 * CSV export of the persistent and pending lists of a pair of campaigns. It is the ONLY CSV path of the palpation report and it goes through the
 * shared `exportRowsToCsv` (client side, UTF-8 BOM, comma, every cell quoted), which this file does not modify. Read-only: it writes a file on the
 * user's machine and nothing else. The export FAILS CLOSED: nothing is written unless the report is complete and ready, the company is valid and
 * every row it was built from belongs to that company. Cells that could run as a spreadsheet formula are neutralised; the technician is never a
 * column; the file name carries dates only (never the name of the company).
 */

export type ExportBlockReason =
  | 'no-tenant'
  | 'not-ready'
  | 'truncated'
  | 'invalid-campaigns'
  | 'same-campaign'
  | 'foreign-company'
  | 'empty';

export interface ExportInput {
  /** Status of the report as the service holds it. Only `listo` (complete and loaded) may be exported. */
  readonly status: ReportStatus;
  /** The active company, or null when it is missing or ambiguous. */
  readonly tenantId: number | null;
  readonly events: readonly PalpationEventRow[];
  readonly herd: readonly PalpationHerdRow[];
  readonly a: Campaign;
  readonly b: Campaign;
}

export type ExportPlan =
  | { readonly ok: true; readonly filename: string; readonly columns: ReadonlyArray<CsvColumn<PairRow>>; readonly rows: readonly PairRow[] }
  | { readonly ok: false; readonly reason: ExportBlockReason };

/** The function that writes the file. A token so tests can capture it; the default is the shared `exportRowsToCsv`. */
export type CsvWriter = typeof exportRowsToCsv;
export const PALPATION_CSV_WRITER = new InjectionToken<CsvWriter>('PALPATION_CSV_WRITER', {
  providedIn: 'root',
  factory: () => exportRowsToCsv,
});

const FORMULA_START = /^[=+\-@\t\r]/;

/**
 * Neutralises a cell that a spreadsheet could run as a formula (it starts with =, +, - or @, or with a tab or a carriage return, even after
 * spaces) by prefixing an apostrophe, so it is read as text. Any other text is returned unchanged. `null` and `undefined` become an empty cell.
 */
export function guardCell(value: string | null | undefined): string {
  const text = value ?? '';
  return FORMULA_START.test(text.trimStart()) || FORMULA_START.test(text) ? `'${text}` : text;
}

/** The file name: dates only, never the name of the company. The campaigns must have valid dates (checked before). */
export function exportFilename(a: Campaign, b: Campaign): string {
  return `palpaciones_vacias_A_${a.from}_${a.to}_B_${b.from}_${b.to}.csv`;
}

/** Columns of the file: group, SINIIGA, fuego, brand, category, current status, and for each campaign date, result, code, condition and flag. */
export function exportColumns(a: Campaign, b: Campaign): ReadonlyArray<CsvColumn<PairRow>> {
  const perCampaign = (campaign: Campaign, pick: (r: PairRow) => PairRow['a']): ReadonlyArray<CsvColumn<PairRow>> => {
    const name = campaign.label.trim();
    return [
      { header: guardCell(`${name} · Fecha`), value: r => guardCell(pick(r).date) },
      { header: guardCell(`${name} · Resultado`), value: r => guardCell(CATEGORY_LABEL[pick(r).category]) },
      { header: guardCell(`${name} · Código`), value: r => guardCell(pick(r).rawCode) },
      { header: guardCell(`${name} · Condición`), value: r => guardCell(pick(r).condition === null ? '' : SUBTYPE_LABEL[pick(r).condition as keyof typeof SUBTYPE_LABEL]) },
      { header: guardCell(`${name} · Código sin confirmar`), value: r => (pick(r).unconfirmed ? 'Sí' : '') },
    ];
  };
  return [
    { header: 'Grupo', value: r => guardCell(GROUP_LABEL[r.group]) },
    { header: 'SINIIGA', value: r => guardCell(r.siniiga) },
    { header: 'Quemado', value: r => guardCell(r.fuego) },
    { header: 'Marca', value: r => guardCell(r.brand) },
    { header: 'Categoría', value: r => guardCell(r.category) },
    { header: 'Estado actual', value: r => guardCell(r.currentStatus) },
    ...perCampaign(a, r => r.a),
    ...perCampaign(b, r => r.b),
  ];
}

/**
 * The cheap part of the guard, usable to enable or disable a button: a valid company first, then the report complete (`truncado` is refused) and
 * ready. Returns the reason it is refused, or null when the report allows an export. The full plan checks more (campaigns, every row).
 */
export function exportReadiness(status: ReportStatus, tenantId: number | null): ExportBlockReason | null {
  if (typeof tenantId !== 'number' || !Number.isInteger(tenantId) || tenantId <= 0) return 'no-tenant';
  if (status === 'truncado') return 'truncated';
  if (status !== 'listo') return 'not-ready';
  return null;
}

/**
 * Decides whether the export may happen and builds it, without writing anything. Checked in this order: a valid company, the report complete
 * (`truncado` is refused: a partial list would look like a complete one), the report ready, two valid and different campaigns, every event and herd
 * row belongs to the active company (row by row, nothing is skipped), and there is something to export.
 */
export function planPairCsv(input: ExportInput): ExportPlan {
  const { status, tenantId, events, herd, a, b } = input;
  const notReady = exportReadiness(status, tenantId);
  if (notReady !== null) return { ok: false, reason: notReady };
  if (a.id === b.id) return { ok: false, reason: 'same-campaign' };
  if (validateCampaigns([a, b]).length > 0) return { ok: false, reason: 'invalid-campaigns' };
  for (const e of events) if (e.id_company !== tenantId) return { ok: false, reason: 'foreign-company' };
  for (const h of herd) if (h.id_company !== tenantId) return { ok: false, reason: 'foreign-company' };

  const { persistent, pending } = pairLists(events, herd, a, b);
  const rows = [...persistent, ...pending];
  if (rows.length === 0) return { ok: false, reason: 'empty' };
  return { ok: true, filename: exportFilename(a, b), columns: exportColumns(a, b), rows };
}

/** Plans the export and, only when it is allowed, writes the file through the writer. Returns the plan so the caller can show why it was refused. */
export function exportPairCsv(input: ExportInput, writer: CsvWriter = exportRowsToCsv): ExportPlan {
  const plan = planPairCsv(input);
  if (plan.ok) writer(plan.rows, plan.columns, plan.filename);
  return plan;
}
