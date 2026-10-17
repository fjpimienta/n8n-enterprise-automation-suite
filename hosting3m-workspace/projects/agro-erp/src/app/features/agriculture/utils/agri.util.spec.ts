import { describe, expect, it } from 'vitest';
import type { LotInput, PlantationInput } from '@core/models/agri.model';
import {
  UNCONFIRMED_MESSAGE,
  buildLotFields,
  buildPlantationFields,
  canAdministerPalm,
  canRecordCensus,
  friendlyGatewayError,
  interpretSpResponse,
  isPossiblyTruncated,
  parseDecimal,
  toBool,
  toInt,
  toNumber,
  todayCdmx,
  validateCensus,
  validateLotInput,
  validatePlantationInput,
  validateRowRange,
} from './agri.util';

const plantation = (o: Partial<PlantationInput> = {}): PlantationInput => ({
  code: 'P-01', name: 'Plantación Uno', state: '', municipality: '', locality: '', latitude: '', longitude: '',
  totalAreaHa: '120', tenure: 'PROPIA', lessorName: '', notes: '', ...o,
});
const lot = (o: Partial<LotInput> = {}): LotInput => ({
  code: 'L-01', name: '', areaHa: '25', plantingDate: '', plantingDateIsApprox: false, varietyId: '', seedSupplier: '',
  plantingPattern: '', spacingM: '', designDensityPlantsHa: '', waterRegime: '', soilType: '', tenure: '', lessorName: '',
  notes: '', ...o,
});

describe('roles (active company role)', () => {
  it('administration is ADMIN / OWNER only', () => {
    expect(['ADMIN', 'owner', 'EDITOR', 'CUSTOMER', null, undefined, ''].map(canAdministerPalm))
      .toEqual([true, true, false, false, false, false, false]);
  });
  it('census is ADMIN / OWNER / EDITOR (CUSTOMER read-only)', () => {
    expect(['ADMIN', 'OWNER', 'editor', 'CUSTOMER', null].map(canRecordCensus)).toEqual([true, true, true, false, false]);
  });
});

describe('gateway values', () => {
  it('parses numerics that arrive as strings', () => {
    expect(toNumber('120.0000')).toBe(120);
    expect(toNumber(' 7 ')).toBe(7);
    expect(toNumber('')).toBeNull();
    expect(toNumber(null)).toBeNull();
    expect(toNumber('abc')).toBeNull();
    expect(toInt('15')).toBe(15);
    expect(toInt(undefined, -1)).toBe(-1);
  });
  it('parses gateway booleans', () => {
    expect([true, 'true', 't', false, 'false', 'f', null].map(toBool)).toEqual([true, true, true, false, false, false, false]);
  });
  it('flags listings that hit the gateway caps', () => {
    expect([1499, 1500, 1501, 2000, 0].map(isPossiblyTruncated)).toEqual([false, true, false, true, false]);
  });
  it('parseDecimal accepts comma decimals and rejects garbage', () => {
    expect(parseDecimal('12,5')).toBe(12.5);
    expect(parseDecimal('')).toBeNull();
    expect(Number.isNaN(parseDecimal('12a'))).toBe(true);
  });
});

describe('interpretSpResponse (fail-closed)', () => {
  it('only error:false + data.success:true is a success', () => {
    expect(interpretSpResponse({ error: false, data: { success: true, created: 3 } }))
      .toEqual({ ok: true, data: { success: true, created: 3 } });
  });
  it('a flagged error shows the procedure message', () => {
    expect(interpretSpResponse({ error: true, message: 'La fila no existe o no pertenece a la empresa activa.' }))
      .toEqual({ ok: false, message: 'La fila no existe o no pertenece a la empresa activa.' });
  });
  it('anything else is "not confirmed", never a silent success', () => {
    for (const res of [null, {}, { error: false }, { error: false, data: {} }, { error: false, data: { success: false } }, 'x', []]) {
      expect(interpretSpResponse(res)).toEqual({ ok: false, message: UNCONFIRMED_MESSAGE });
    }
  });
  it('constraint names become Spanish messages', () => {
    expect(friendlyGatewayError('duplicate key value violates unique constraint "uq_agri_lots_code_active"'))
      .toBe('Ya existe un lote activo con esa clave en esta plantación.');
    expect(friendlyGatewayError('')).toBe('El servidor reportó un error al procesar la solicitud.');
  });
});

describe('validateRowRange (mirrors sp_agri_bulk_create_rows)', () => {
  it('accepts a range and a single row (from = to)', () => {
    expect(validateRowRange('1', '50', '20')).toBeNull();
    expect(validateRowRange('7', '7', '0')).toBeNull();
  });
  it('rejects invalid ranges and sizes', () => {
    expect(validateRowRange('0', '5', '20')).toMatch(/1 o mayor/);
    expect(validateRowRange('10', '5', '20')).toMatch(/no puede ser menor/);
    expect(validateRowRange('1', '501', '20')).toMatch(/Máximo 500/);
    expect(validateRowRange('1', '2', '-1')).toMatch(/entre 0 y 10000/);
    expect(validateRowRange('1', '2', '10001')).toMatch(/entre 0 y 10000/);
    expect(validateRowRange('a', '2', '1')).toMatch(/enteros/);
  });
});

describe('validateCensus (final values, like sp_agri_record_row_census)', () => {
  const base = { alive: '18', positions: '', currentPositions: 20, reason: 'CENSO' as const, censusDate: '', today: '2026-10-17', canChangePositions: false };
  it('accepts a normal count', () => expect(validateCensus(base)).toBeNull());
  it('rejects alive above the final positions', () => {
    expect(validateCensus({ ...base, alive: '21' })).toMatch(/no pueden superar los 20/);
    expect(validateCensus({ ...base, alive: '20', positions: '15', canChangePositions: true })).toMatch(/no pueden superar los 15/);
  });
  it('an EDITOR can send the current positions but not change them', () => {
    expect(validateCensus({ ...base, positions: '20' })).toBeNull();
    expect(validateCensus({ ...base, positions: '25' })).toMatch(/Solo un administrador/);
    expect(validateCensus({ ...base, alive: '24', positions: '25', canChangePositions: true })).toBeNull();
  });
  it('requires a reason and rejects future dates', () => {
    expect(validateCensus({ ...base, reason: '' })).toMatch(/motivo/);
    expect(validateCensus({ ...base, censusDate: '2026-10-18' })).toMatch(/futura/);
  });
});

describe('plantation and lot forms', () => {
  it('validates plantations like the 080 CHECKs', () => {
    expect(validatePlantationInput(plantation())).toBeNull();
    expect(validatePlantationInput(plantation({ totalAreaHa: '0' }))).toMatch(/mayor que 0/);
    expect(validatePlantationInput(plantation({ latitude: '17.5' }))).toMatch(/juntas/);
    expect(validatePlantationInput(plantation({ latitude: '95', longitude: '-92' }))).toMatch(/latitud/i);
    expect(validatePlantationInput(plantation({ tenure: 'RENTADA' }))).toMatch(/arrendador/i);
  });
  it('builds plantation fields without id / id_company / is_default and drops the lessor unless rented', () => {
    const fields = buildPlantationFields(plantation({ lessorName: 'X', latitude: '17,5', longitude: '-92' }));
    expect(fields).not.toHaveProperty('id');
    expect(fields).not.toHaveProperty('id_company');
    expect(fields).not.toHaveProperty('is_default');
    expect(fields['lessor_name']).toBeNull();
    expect(fields['latitude']).toBe(17.5);
    expect(fields['total_area_ha']).toBe(120);
  });
  it('a lot with tenure "same as the plantation" sends NULL tenure and NULL lessor', () => {
    const fields = buildLotFields(lot({ tenure: '', lessorName: 'ignored' }));
    expect(fields['tenure']).toBeNull();
    expect(fields['lessor_name']).toBeNull();
    expect(buildLotFields(lot({ tenure: 'RENTADA', lessorName: 'Ejido' }))['lessor_name']).toBe('Ejido');
  });
  it('validates lots', () => {
    expect(validateLotInput(lot(), '2026-10-17')).toBeNull();
    expect(validateLotInput(lot({ areaHa: '' }), '2026-10-17')).toMatch(/mayor que 0/);
    expect(validateLotInput(lot({ plantingDate: '2026-10-18' }), '2026-10-17')).toMatch(/futura/);
    expect(validateLotInput(lot({ tenure: 'RENTADA' }), '2026-10-17')).toMatch(/arrendador/i);
    expect(validateLotInput(lot({ designDensityPlantsHa: '0' }), '2026-10-17')).toMatch(/densidad/);
  });
});

describe('todayCdmx', () => {
  it('uses America/Mexico_City, not UTC', () => {
    // 2026-10-18 03:00 UTC is still 2026-10-17 in CDMX (UTC-6).
    expect(todayCdmx(new Date('2026-10-18T03:00:00Z'))).toBe('2026-10-17');
  });
});
