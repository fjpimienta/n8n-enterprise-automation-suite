import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { GOLDEN, GOLDEN_A, GOLDEN_B, GOLDEN_MATRIX_ONLY_B, goldenData } from '../testing/palpation-golden.fixtures';
import { eventRow, herdRow } from '../testing/palpation.fixtures';
import { ReportStatus } from '../models/palpation.types';
import { exportRowsToCsv } from '@shared/utils/csv-export.util';
import {
  CsvWriter,
  ExportInput,
  campaignRangeLabel,
  exportCellFilename,
  exportColumns,
  exportFilename,
  exportPairCsv,
  exportReadiness,
  guardCell,
  planPairCsv,
  siniigaSerieArete,
} from './palpation-campaign-export';
import { exportBlockText } from './palpation-campaign-view';
import { Campaign } from './palpation-campaigns';
import { MatrixCell } from './palpation-matrix-cells';

const TENANT = 9101;
const { events, herd } = goldenData();
const input = (over: Partial<ExportInput> = {}): ExportInput => ({ status: 'listo', tenantId: TENANT, events, herd, a: GOLDEN_A, b: GOLDEN_B, ...over });

describe('guardCell (spreadsheet formula injection)', () => {
  it.each(['=1+1', '+SUM(A1)', '-2+3', '@cmd', '=HYPERLINK("http://x")'])('prefixes an apostrophe to %s', value => {
    expect(guardCell(value)).toBe(`'${value}`);
  });

  it('also neutralises a tab or a carriage return and a formula that follows spaces', () => {
    expect(guardCell('\t=1')).toBe("'\t=1");
    expect(guardCell('\r=1')).toBe("'\r=1");
    expect(guardCell('  =1+1')).toBe("'  =1+1");
  });

  it('leaves ordinary text, codes, dates and numbers unchanged, and turns null into an empty cell', () => {
    for (const ok of ['DF15', 'YCL1', 'UNE', 'Estática (UNE)', '2026-08-03', '9999000123', 'ZZ1', 'Q005', 'Vacía', 'a=b', 'x-y', '']) expect(guardCell(ok)).toBe(ok);
    expect(guardCell(null)).toBe('');
    expect(guardCell(undefined)).toBe('');
  });
});

describe('siniigaSerieArete (the paper-form format SERIE-ARETE)', () => {
  it('writes a 10-digit SINIIGA as 6 digits, a hyphen and 4 digits', () => {
    expect(siniigaSerieArete('0700000001')).toBe('070000-0001');
    expect(siniigaSerieArete('2712345678')).toBe('271234-5678');
    expect(siniigaSerieArete('9999000001')).toBe('999900-0001');
  });

  it('keeps the leading zero, which a spreadsheet would drop from a plain number', () => {
    const out = siniigaSerieArete('0700000001');
    expect(out.startsWith('07')).toBe(true);
    expect(out).toBe('070000-0001');
    expect(Number(out.replace('-', ''))).not.toBe(Number(out)); // it is text with a hyphen, not a number that reads as 7000000
    expect(Number.isNaN(Number(out))).toBe(true);
  });

  it('leaves every other value untouched: other lengths, placeholders, letters, spaces, brand and fuego', () => {
    for (const other of ['070000000', '07000000010', 'S/N-00001', '07000A0001', ' 0700000001', '0700000001 ', '070000-0001', 'ZZ1 100', '12345', '']) {
      expect(siniigaSerieArete(other)).toBe(other);
    }
  });

  it('turns null and undefined into an empty cell', () => {
    expect(siniigaSerieArete(null)).toBe('');
    expect(siniigaSerieArete(undefined)).toBe('');
  });

  it('never produces a cell that starts with a formula character', () => {
    for (const value of ['0700000001', '9999000001', '2712345678', '-700000001', '=0700000001', '+0700000001', '@0700000001']) {
      expect(/^[=+\-@\t\r]/.test(guardCell(siniigaSerieArete(value)).trimStart())).toBe(false);
    }
  });
});

describe('the SINIIGA column of the file', () => {
  const sin = (id: string, rfid: string | null) => herdRow({ livestock_id: id, rfid_siniiga: rfid, numero_fuego: '77', brand_code: 'ZZ1', category: 'VACA', current_status: 'ACTIVO' });
  const ev = (id: string) => eventRow({ health_log_id: `e-${id}`, livestock_id: id, event_date: '2026-08-03', result: 'VACÍA' });
  const cells = (rfid: string | null) => {
    const p = planPairCsv(input({ events: [ev('X')], herd: [sin('X', rfid)] }));
    if (!p.ok) throw new Error('unexpected');
    return p.columns.map(c => c.value(p.rows[0] as (typeof p.rows)[number]));
  };

  it('writes the official SINIIGA of an animal as SERIE-ARETE with its leading zero', () => {
    expect(cells('0700000001')[1]).toBe('070000-0001');
  });

  it('leaves an identifier that is not an official SINIIGA out of the SINIIGA column, and keeps brand and fuego as they are', () => {
    for (const other of ['S/N-00001', '70000000', '07000000010', null]) {
      const row = cells(other);
      expect(row[1]).toBe('');
      expect(row[2]).toBe('77');
      expect(row[3]).toBe('ZZ1');
    }
  });

  it('no cell of the whole golden file starts with a formula character, SINIIGA included', () => {
    const p = planPairCsv(input());
    if (!p.ok) throw new Error('unexpected');
    const all = p.rows.flatMap(r => p.columns.map(c => c.value(r)));
    expect(all.length).toBe(50 * 16);
    expect(all.some(cell => /^[=+\-@\t\r]/.test(cell.trimStart()))).toBe(false);
    const sinCells = p.rows.map(r => p.columns[1]?.value(r) ?? '').filter(c => c !== '');
    expect(sinCells.length).toBeGreaterThan(0);
    expect(sinCells.every(c => /^\d{6}-\d{4}$/.test(c))).toBe(true);
  });

  it('the file written through the shared util has the SERIE-ARETE value as quoted text', async () => {
    const e = [ev('X')];
    const h = [sin('X', '0700000001')];
    const blobs: Blob[] = [];
    vi.stubGlobal('URL', Object.assign(URL, { createObjectURL: (b: Blob) => { blobs.push(b); return 'blob:t'; }, revokeObjectURL: () => undefined }));
    vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(() => undefined);
    try {
      expect(exportPairCsv(input({ events: e, herd: h }), exportRowsToCsv).ok).toBe(true);
      const text = await new Promise<string>((resolve, reject) => {
        const reader = new FileReader();
        reader.onload = () => resolve(new TextDecoder('utf-8', { ignoreBOM: true }).decode(new Uint8Array(reader.result as ArrayBuffer)));
        reader.onerror = () => reject(reader.error);
        reader.readAsArrayBuffer(blobs[0] as Blob);
      });
      expect(text.split('\n')[1]).toContain('"070000-0001"');
    } finally {
      vi.restoreAllMocks();
      vi.unstubAllGlobals();
    }
  });
});

describe('campaignRangeLabel', () => {
  it('is one date for a single day and "desde a hasta" for a range', () => {
    expect(campaignRangeLabel({ from: '2026-08-03', to: '2026-08-03' })).toBe('2026-08-03');
    expect(campaignRangeLabel({ from: '2026-11-11', to: '2026-11-12' })).toBe('2026-11-11 a 2026-11-12');
  });
});

describe('exportFilename', () => {
  it('has dates only: no company name, no label, no identifier', () => {
    const name = exportFilename(GOLDEN_A, GOLDEN_B);
    expect(name).toBe('palpaciones_vacias_A_2026-08-03_2026-08-03_B_2026-11-01_2026-11-30.csv');
    expect(name).toMatch(/^[A-Za-z0-9_.-]+$/);
  });

  it('does not use the user-defined labels, which could hold anything', () => {
    const odd: Campaign = { id: 'x', label: 'Rancho "El Real" =1+1', from: '2026-08-03', to: '2026-08-03' };
    expect(exportFilename(odd, GOLDEN_B)).not.toContain('Rancho');
    expect(exportFilename(odd, GOLDEN_B)).not.toContain('=');
  });
});

describe('planPairCsv: what is exported', () => {
  const plan = planPairCsv(input());
  if (!plan.ok) throw new Error('the golden dataset must be exportable');

  it('has one row for each of the 31 persistent and 19 pending animals, in the two groups', () => {
    expect(plan.rows.length).toBe(GOLDEN.vaciaVacia + GOLDEN.vaciaNoPalpada);
    expect(plan.rows.filter(r => r.group === 'PERSISTENT').length).toBe(GOLDEN.vaciaVacia);
    expect(plan.rows.filter(r => r.group === 'PENDING').length).toBe(GOLDEN.vaciaNoPalpada);
  });

  it('has the columns: group, SINIIGA, quemado, brand, category, status, and date, result, code, condition and flag for each campaign, each with its date range', () => {
    expect(plan.columns.map(c => c.header)).toEqual([
      'Grupo', 'SINIIGA', 'Quemado', 'Marca', 'Categoría', 'Estado actual',
      'Fecha (2026-08-03)', 'Resultado (2026-08-03)', 'Código (2026-08-03)', 'Condición (2026-08-03)', 'Código sin confirmar (2026-08-03)',
      'Fecha (2026-11-01 a 2026-11-30)', 'Resultado (2026-11-01 a 2026-11-30)', 'Código (2026-11-01 a 2026-11-30)', 'Condición (2026-11-01 a 2026-11-30)', 'Código sin confirmar (2026-11-01 a 2026-11-30)',
    ]);
  });

  it('never has a technician column or value', () => {
    expect(plan.columns.some(c => /t[eé]cnico|technician/i.test(c.header))).toBe(false);
    const withTech = planPairCsv(input({ events: events.map(e => ({ ...e, technician: 'Técnico demo 1' })) }));
    if (!withTech.ok) throw new Error('unexpected');
    const text = withTech.rows.map(r => withTech.columns.map(c => c.value(r)).join('|')).join('\n');
    expect(text).not.toContain('Técnico');
  });

  it('writes UNE in August and ESTATICA in November with the condition Estática (UNE) in both, and the unconfirmed codes as typed with the flag', () => {
    const cells = (r: (typeof plan.rows)[number]) => plan.columns.map(c => c.value(r));
    const une = plan.rows.find(r => r.a.rawCode === 'UNE' && r.b.rawCode === 'ESTATICA');
    const row = cells(une as NonNullable<typeof une>);
    expect(row.slice(6, 11)).toEqual(['2026-08-03', 'Vacía', 'UNE', 'Estática (UNE)', '']);
    expect(row[12]).toBe('Vacía');
    expect(row.slice(13, 16)).toEqual(['ESTATICA', 'Estática (UNE)', '']);
    const unconfirmed = plan.rows.find(r => r.a.unconfirmed);
    const u = cells(unconfirmed as NonNullable<typeof unconfirmed>);
    expect(['DF15', 'YF15', 'DCL1', 'YCL1']).toContain(u[8]);
    expect(u.slice(9, 11)).toEqual(['', 'Sí']);
  });

  it('writes the pending animals with an empty campaign B: no date, "Sin registro en esa campaña", no code', () => {
    const pending = plan.rows.find(r => r.group === 'PENDING');
    const cells = plan.columns.map(c => c.value(pending as NonNullable<typeof pending>));
    expect(cells[0]).toBe('Vacía en A y no palpada en B (seguimiento)');
    expect(cells.slice(11, 16)).toEqual(['', 'Sin registro en esa campaña', '', '', '']);
  });

  it('writes SINIIGA, fuego, brand, category and status from the herd', () => {
    const sin = plan.rows.find(r => r.siniiga !== null);
    const v = plan.columns.map(c => c.value(sin as NonNullable<typeof sin>));
    expect(v[1]).toMatch(/^\d{6}-\d{4}$/); // SERIE-ARETE, as on the paper form
    expect(v[4]).toMatch(/^(VACA|NOVILLONA)$/);
    expect(v[5]).toMatch(/^(ACTIVO|VENDIDO)$/);
    const noSin = plan.rows.find(r => r.siniiga === null);
    const w = plan.columns.map(c => c.value(noSin as NonNullable<typeof noSin>));
    expect(w[1]).toBe('');
    expect(w[3]).toBe('ZZ1');
  });

  it('neutralises a dangerous value anywhere in a row, including a code typed by the vet and a campaign label in a header', () => {
    const evil = [
      eventRow({ health_log_id: 'e1', livestock_id: 'E', event_date: '2026-08-03', result: 'VACÍA', mapping_status: 'UNMAPPED', raw_code: '=cmd|\' /C calc\'!A0' }),
    ];
    const h = [herdRow({ livestock_id: 'E', rfid_siniiga: null, numero_fuego: '@1', brand_code: '+9', category: '-VACA', current_status: '=ACTIVO' })];
    const bad: Campaign = { id: 'b', label: '=HYPERLINK("x")', from: '2026-11-01', to: '2026-11-30' };
    const p = planPairCsv(input({ events: evil, herd: h, b: bad }));
    if (!p.ok) throw new Error('unexpected');
    const cells = [...p.columns.map(c => c.header), ...p.columns.map(c => c.value(p.rows[0] as (typeof p.rows)[number]))];
    for (const cell of cells) expect(/^[=+\-@\t\r]/.test(cell.trimStart())).toBe(false);
    expect(cells).toContain("'=cmd|' /C calc'!A0");
    expect(cells).toContain("'@1");
    // the user-given label never reaches the file: the headers carry dates only
    expect(p.columns.map(c => c.header).join('|')).not.toContain('HYPERLINK');
  });

  it('writes the date range of each campaign in every per-campaign header: a single day as one date, a range as "desde a hasta"', () => {
    const cols = exportColumns({ ...GOLDEN_A, label: 'Agosto' }, { ...GOLDEN_B, label: 'Noviembre' });
    const headers = cols.map(c => c.header);
    expect(cols.length).toBe(16);
    expect(headers.filter(h => h.endsWith('(2026-08-03)')).length).toBe(5);
    expect(headers.filter(h => h.endsWith('(2026-11-01 a 2026-11-30)')).length).toBe(5);
    expect(headers.slice(0, 6)).toEqual(['Grupo', 'SINIIGA', 'Quemado', 'Marca', 'Categoría', 'Estado actual']);
    // the file is understandable without the labels: they are not in the headers
    expect(headers.join('|')).not.toMatch(/Agosto|Noviembre|Campaña/);
  });

  it('shows two campaigns of the same length or the same label apart by their dates alone', () => {
    const a: Campaign = { id: 'a', label: 'Monta', from: '2026-08-03', to: '2026-08-03' };
    const b: Campaign = { id: 'b', label: 'Monta 2', from: '2026-11-11', to: '2026-11-12' };
    const headers = exportColumns(a, b).map(c => c.header);
    expect(new Set(headers).size).toBe(headers.length); // no two columns share a header
    expect(headers).toContain('Resultado (2026-08-03)');
    expect(headers).toContain('Resultado (2026-11-11 a 2026-11-12)');
  });

  it('keeps the formula protection on every header', () => {
    const odd: Campaign = { id: 'a', label: 'x', from: '2026-08-03', to: '2026-08-03' };
    for (const header of exportColumns(odd, GOLDEN_B).map(c => c.header)) expect(/^[=+\-@\t\r]/.test(header.trimStart())).toBe(false);
  });
});

describe('planPairCsv: fail closed', () => {
  const blocked = (over: Partial<ExportInput>) => {
    const p = planPairCsv(input(over));
    return p.ok ? 'OK' : p.reason;
  };

  it('is allowed only when the report is complete and ready', () => {
    expect(blocked({})).toBe('OK');
  });

  it.each(['cargando', 'error', 'vacio', 'sin-tenant', 'sin-permiso'] as ReportStatus[])('refuses while the report is "%s"', status => {
    expect(blocked({ status })).toBe('not-ready');
  });

  it('refuses a truncated report, so a partial list is never exported as if it were complete', () => {
    expect(blocked({ status: 'truncado' })).toBe('truncated');
  });

  it.each([null, 0, -1, 1.5, Number.NaN])('refuses without a valid company (%s)', tenantId => {
    expect(blocked({ tenantId })).toBe('no-tenant');
  });

  it('checks the company before anything else: no company and a truncated report is "no-tenant"', () => {
    expect(blocked({ tenantId: null, status: 'truncado' })).toBe('no-tenant');
  });

  it('refuses when ANY event has another id_company, however late in the list it is', () => {
    const foreign = events.map((e, i) => (i === events.length - 1 ? { ...e, id_company: 9102 } : e));
    expect(blocked({ events: foreign })).toBe('foreign-company');
    const first = events.map((e, i) => (i === 0 ? { ...e, id_company: 9102 } : e));
    expect(blocked({ events: first })).toBe('foreign-company');
  });

  it('refuses when ANY herd row has another id_company', () => {
    expect(blocked({ herd: herd.map((h, i) => (i === herd.length - 1 ? { ...h, id_company: 9102 } : h)) })).toBe('foreign-company');
  });

  it('refuses a row of another company even if it would not be in the exported lists', () => {
    const extra = [...events, eventRow({ id_company: 9102, health_log_id: 'zz', livestock_id: 'unrelated', event_date: '2026-01-01', result: 'VACÍA' })];
    expect(blocked({ events: extra })).toBe('foreign-company');
  });

  it('refuses invalid campaigns, the same campaign twice, overlapping campaigns and a label that repeats', () => {
    expect(blocked({ a: { ...GOLDEN_A, from: '2026-13-01' } })).toBe('invalid-campaigns');
    expect(blocked({ b: { ...GOLDEN_B, from: '2026-11-30', to: '2026-11-01' } })).toBe('invalid-campaigns');
    expect(blocked({ b: { ...GOLDEN_B, from: '2026-08-01', to: '2026-08-30' } })).toBe('invalid-campaigns');
    expect(blocked({ b: { ...GOLDEN_B, label: GOLDEN_A.label } })).toBe('invalid-campaigns');
    expect(blocked({ b: GOLDEN_A })).toBe('same-campaign');
  });

  it('refuses when there is nothing to export', () => {
    expect(blocked({ events: [], herd: [] })).toBe('empty');
  });

  it('has a Spanish message for every reason', () => {
    for (const reason of ['no-tenant', 'not-ready', 'truncated', 'invalid-campaigns', 'same-campaign', 'foreign-company', 'empty'] as const) {
      expect(exportBlockText(reason).length).toBeGreaterThan(15);
    }
    expect(exportBlockText('truncated')).toContain('incompleto');
  });
});

describe('exportReadiness (the cheap part of the guard)', () => {
  it('allows an export only for a complete, ready report of a valid company', () => {
    expect(exportReadiness('listo', TENANT)).toBeNull();
    expect(exportReadiness('truncado', TENANT)).toBe('truncated');
    expect(exportReadiness('cargando', TENANT)).toBe('not-ready');
    expect(exportReadiness('listo', null)).toBe('no-tenant');
    expect(exportReadiness('truncado', null)).toBe('no-tenant');
  });
});

describe('exportPairCsv', () => {
  it('does not call the writer when refused, and calls it once with the plan when allowed', () => {
    const writer = vi.fn() as unknown as CsvWriter;
    expect(exportPairCsv(input({ status: 'truncado' }), writer).ok).toBe(false);
    expect(exportPairCsv(input({ tenantId: null }), writer).ok).toBe(false);
    expect(exportPairCsv(input({ events: events.map((e, i) => (i === 3 ? { ...e, id_company: 9102 } : e)) }), writer).ok).toBe(false);
    expect(writer).not.toHaveBeenCalled();
    expect(exportPairCsv(input(), writer).ok).toBe(true);
    expect(writer).toHaveBeenCalledTimes(1);
    const [rows, columns, filename] = (writer as unknown as ReturnType<typeof vi.fn>).mock.calls[0] as [unknown[], unknown[], string];
    expect(rows.length).toBe(50);
    expect(columns.length).toBe(16);
    expect(filename).toBe('palpaciones_vacias_A_2026-08-03_2026-08-03_B_2026-11-01_2026-11-30.csv');
  });
});

/** The bytes of a Blob (jsdom has no Blob.stream, and a text read would hide the byte order mark). */
function bytesOf(blob: Blob): Promise<Uint8Array> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(new Uint8Array(reader.result as ArrayBuffer));
    reader.onerror = () => reject(reader.error);
    reader.readAsArrayBuffer(blob);
  });
}
const decode = (bytes: Uint8Array): string => new TextDecoder('utf-8', { ignoreBOM: true }).decode(bytes);

describe('through the shared exportRowsToCsv (unmodified)', () => {
  let blobs: Blob[];
  let names: string[];

  beforeEach(() => {
    blobs = [];
    names = [];
    vi.stubGlobal('URL', Object.assign(URL, {
      createObjectURL: (b: Blob) => { blobs.push(b); return 'blob:test'; },
      revokeObjectURL: () => undefined,
    }));
    vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(function (this: HTMLAnchorElement) { names.push(this.download); });
  });
  afterEach(() => {
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
  });

  it('writes a UTF-8 file with a BOM, comma separators and every cell quoted, for the 50 animals plus the header', async () => {
    expect(exportPairCsv(input(), exportRowsToCsv).ok).toBe(true);
    expect(names).toEqual(['palpaciones_vacias_A_2026-08-03_2026-08-03_B_2026-11-01_2026-11-30.csv']);
    const bytes = await bytesOf(blobs[0] as Blob);
    const text = decode(bytes);
    expect(blobs[0]?.type).toContain('text/csv');
    expect([...bytes.slice(0, 3)]).toEqual([0xef, 0xbb, 0xbf]); // UTF-8 byte order mark, so Excel reads the accents
    expect(text.charCodeAt(0)).toBe(0xfeff);
    const lines = text.slice(1).split('\n');
    expect(lines.length).toBe(51);
    expect(lines[0]?.startsWith('"Grupo","SINIIGA","Quemado","Marca","Categoría","Estado actual","Fecha (2026-08-03)","Resultado (2026-08-03)"')).toBe(true);
    expect(lines[0]).toContain('"Resultado (2026-11-01 a 2026-11-30)"');
    expect(lines[1]?.startsWith('"Vacía en A y en B (persistente)"')).toBe(true);
    expect(lines[1]?.split('","').length).toBe(16);
    expect(text).not.toContain('Técnico');
    expect(text).not.toMatch(/Rancho|Hosting3m/i);
  });

  it('escapes quotes inside a cell and keeps a dangerous cell as text in the file', async () => {
    const e = [eventRow({ health_log_id: 'q', livestock_id: 'Q', event_date: '2026-08-03', result: 'VACÍA', mapping_status: 'UNMAPPED', raw_code: '=1+1,"x"' })];
    const h = [herdRow({ livestock_id: 'Q', rfid_siniiga: '9999000001' })];
    expect(exportPairCsv(input({ events: e, herd: h }), exportRowsToCsv).ok).toBe(true);
    const text = decode(await bytesOf(blobs[0] as Blob));
    expect(text).toContain('"\'=1+1,""x"""');
  });

  it('writes nothing, not even an empty file, when the export is refused', () => {
    exportPairCsv(input({ status: 'truncado' }), exportRowsToCsv);
    expect(blobs.length).toBe(0);
    expect(names.length).toBe(0);
  });
});

describe('export of the list behind one matrix cell', () => {
  const matrix = goldenData(GOLDEN_MATRIX_ONLY_B);
  const cellInput = (cell: MatrixCell | null, over: Partial<ExportInput> = {}): ExportInput => ({
    status: 'listo', tenantId: TENANT, events: matrix.events, herd: matrix.herd, a: GOLDEN_A, b: GOLDEN_B, cell, ...over,
  });
  const NO_PRENADA: MatrixCell = { from: 'NO_PALPADA', to: 'PREÑADA' };
  const NO_VACIA: MatrixCell = { from: 'NO_PALPADA', to: 'VACÍA' };

  it('has the A and B date ranges and the cell identifier in the file name, and nothing else', () => {
    const name = exportCellFilename(GOLDEN_A, GOLDEN_B, NO_PRENADA);
    expect(name).toBe('palpaciones_celda_sin-registro.prenada_A_2026-08-03_2026-08-03_B_2026-11-01_2026-11-30.csv');
    expect(name).toMatch(/^[A-Za-z0-9_.-]+$/);
    const plan = planPairCsv(cellInput(NO_PRENADA));
    expect(plan.ok && plan.filename).toBe(name);
    const odd: Campaign = { id: 'x', label: 'Rancho "El Real" =1+1', from: '2026-08-03', to: '2026-08-03' };
    expect(exportCellFilename(odd, GOLDEN_B, NO_VACIA)).not.toMatch(/Rancho|=|"/);
  });

  it('exports the 32 and the 52 animals of the two big "sin registro en A" cells, and the 7 / 11 / 25 / 31 / 27 / 19 of the others', () => {
    const count = (cell: MatrixCell): number => {
      const p = planPairCsv(cellInput(cell));
      return p.ok ? p.rows.length : -1;
    };
    expect(count(NO_PRENADA)).toBe(32);
    expect(count(NO_VACIA)).toBe(52);
    expect(count({ from: 'PREÑADA', to: 'PREÑADA' })).toBe(7);
    expect(count({ from: 'PREÑADA', to: 'VACÍA' })).toBe(11);
    expect(count({ from: 'VACÍA', to: 'PREÑADA' })).toBe(25);
    expect(count({ from: 'VACÍA', to: 'VACÍA' })).toBe(31);
    expect(count({ from: 'PREÑADA', to: 'NO_PALPADA' })).toBe(27);
    expect(count({ from: 'VACÍA', to: 'NO_PALPADA' })).toBe(19);
  });

  it('has the same 16 columns and headers with the date ranges as the follow-up export, and names the cell in the "Grupo" column', () => {
    const plan = planPairCsv(cellInput(NO_PRENADA));
    if (!plan.ok) throw new Error('unexpected');
    const follow = planPairCsv(input());
    if (!follow.ok) throw new Error('unexpected');
    expect(plan.columns.map(c => c.header)).toEqual(follow.columns.map(c => c.header));
    expect(plan.columns[8]?.header).toBe('Código (2026-08-03)');
    const row = plan.rows[0] as (typeof plan.rows)[number];
    const cells = plan.columns.map(c => c.value(row));
    expect(cells[0]).toBe('Sin registro en (2026-08-03) y Preñada en (2026-11-01 a 2026-11-30)');
    expect(plan.rows.every(r => r.group === 'CELL')).toBe(true);
  });

  it('writes SINIIGA as SERIE-ARETE, no technician, the empty campaign as "Sin registro en esa campaña" and no formula cell', () => {
    const withTech = matrix.events.map(e => ({ ...e, technician: 'Técnico demo 1' }));
    const plan = planPairCsv(cellInput(NO_VACIA, { events: withTech }));
    if (!plan.ok) throw new Error('unexpected');
    const all = plan.rows.flatMap(r => plan.columns.map(c => c.value(r)));
    expect(all.join('|')).not.toContain('Técnico');
    expect(plan.columns.some(c => /t[eé]cnico/i.test(c.header))).toBe(false);
    expect(all.some(c => /^[=+\-@\t\r]/.test(c.trimStart()))).toBe(false);
    const first = plan.rows.find(r => r.siniiga !== null) as (typeof plan.rows)[number];
    expect(plan.columns[1]?.value(first)).toMatch(/^\d{6}-\d{4}$/);
    const a = plan.columns.slice(6, 11).map(c => c.value(first));
    expect(a).toEqual(['', 'Sin registro en esa campaña', '', '', '']);
  });

  it('has the same fail-closed rules as the follow-up export', () => {
    const blocked = (over: Partial<ExportInput>) => {
      const p = planPairCsv(cellInput(NO_PRENADA, over));
      return p.ok ? 'OK' : p.reason;
    };
    expect(blocked({})).toBe('OK');
    expect(blocked({ status: 'truncado' })).toBe('truncated');
    expect(blocked({ status: 'cargando' })).toBe('not-ready');
    expect(blocked({ tenantId: null })).toBe('no-tenant');
    expect(blocked({ tenantId: 0 })).toBe('no-tenant');
    expect(blocked({ b: GOLDEN_A })).toBe('same-campaign');
    expect(blocked({ b: { ...GOLDEN_B, from: '2026-08-01', to: '2026-08-30' } })).toBe('invalid-campaigns');
    expect(blocked({ events: matrix.events.map((e, i) => (i === matrix.events.length - 1 ? { ...e, id_company: 9102 } : e)) })).toBe('foreign-company');
    expect(blocked({ herd: matrix.herd.map((h, i) => (i === 0 ? { ...h, id_company: 9102 } : h)) })).toBe('foreign-company');
    expect(blocked({ events: [], herd: [] })).toBe('empty');
  });

  it('refuses an empty cell and the cell that can never hold an animal, without writing', () => {
    const writer = vi.fn() as unknown as CsvWriter;
    for (const cell of [{ from: 'NO_PALPADA', to: 'NO_PALPADA' }, { from: 'SIN_INTERPRETAR', to: 'RANCHO' }] as MatrixCell[]) {
      const plan = exportPairCsv(cellInput(cell), writer);
      expect(plan.ok).toBe(false);
      expect(plan.ok ? '' : plan.reason).toBe('empty');
    }
    expect(writer).not.toHaveBeenCalled();
  });

  it('does not call the writer when refused, and writes once with the rows and the cell file name when allowed', () => {
    const writer = vi.fn() as unknown as CsvWriter;
    expect(exportPairCsv(cellInput(NO_PRENADA, { status: 'truncado' }), writer).ok).toBe(false);
    expect(exportPairCsv(cellInput(NO_PRENADA, { tenantId: null }), writer).ok).toBe(false);
    expect(writer).not.toHaveBeenCalled();
    expect(exportPairCsv(cellInput(NO_PRENADA), writer).ok).toBe(true);
    const [rows, columns, filename] = (writer as unknown as ReturnType<typeof vi.fn>).mock.calls[0] as [unknown[], unknown[], string];
    expect(rows.length).toBe(32);
    expect(columns.length).toBe(16);
    expect(filename).toContain('palpaciones_celda_sin-registro.prenada_A_2026-08-03_2026-08-03_B_2026-11-01_2026-11-30');
  });

  it('without a cell it still exports the two follow-up groups, as before', () => {
    const p = planPairCsv(cellInput(null));
    expect(p.ok && p.filename).toBe('palpaciones_vacias_A_2026-08-03_2026-08-03_B_2026-11-01_2026-11-30.csv');
    expect(p.ok && p.rows.length).toBe(50);
  });
});
