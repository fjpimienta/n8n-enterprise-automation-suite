/**
 * Pure rules of the palm screens. They mirror migration 080 so the user gets feedback before the
 * round-trip; the database enforces every one of them regardless.
 */
import type { CensusReason, LotInput, PlantationInput } from '@core/models/agri.model';

// ---------------------------------------------------------------------------------------------------
// Roles (always the role of the ACTIVE company: tenantService.activeTenant()?.role, never the JWT role)
// ---------------------------------------------------------------------------------------------------

const ADMIN_ROLES = new Set(['ADMIN', 'OWNER']);
const CENSUS_ROLES = new Set(['ADMIN', 'OWNER', 'EDITOR']);

/** Plantations, lots, rows and planting positions: ADMIN / OWNER (crud_models + the procedures). */
export function canAdministerPalm(role: string | null | undefined): boolean {
  return ADMIN_ROLES.has((role ?? '').toUpperCase());
}

/** Recording a count is a field operation: ADMIN, OWNER and EDITOR (CUSTOMER is read-only). */
export function canRecordCensus(role: string | null | undefined): boolean {
  return CENSUS_ROLES.has((role ?? '').toUpperCase());
}

// ---------------------------------------------------------------------------------------------------
// Gateway values (numerics arrive as strings; booleans as true/'true'/'t')
// ---------------------------------------------------------------------------------------------------

export function toNumber(value: unknown): number | null {
  if (value === null || value === undefined) return null;
  if (typeof value === 'number') return Number.isFinite(value) ? value : null;
  const text = String(value).trim();
  if (text === '') return null;
  const n = Number(text);
  return Number.isFinite(n) ? n : null;
}

export function toInt(value: unknown, fallback = 0): number {
  const n = toNumber(value);
  return n === null ? fallback : Math.trunc(n);
}

export function toBool(value: unknown): boolean {
  return value === true || value === 'true' || value === 't';
}

export function blankToNull(value: string | null | undefined): string | null {
  const text = (value ?? '').trim();
  return text === '' ? null : text;
}

/** The gateway caps getall at 1500 (default) / 2000 (max): exactly those counts may be truncated. */
export function isPossiblyTruncated(count: number): boolean {
  return count === 1500 || count === 2000;
}

// ---------------------------------------------------------------------------------------------------
// Responses and errors
// ---------------------------------------------------------------------------------------------------

export type SpOutcome<T = Record<string, unknown>> = { ok: true; data: T } | { ok: false; message: string };

export const UNCONFIRMED_MESSAGE = 'El servidor no confirmó la operación. Revisa la lista antes de reintentar.';

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

/**
 * Fail-closed reading of a call_sp response: only `error === false` AND `data.success === true` counts.
 * The procedure's own message is shown only when the gateway explicitly flags the error.
 */
export function interpretSpResponse<T = Record<string, unknown>>(res: unknown): SpOutcome<T> {
  if (!isRecord(res)) return { ok: false, message: UNCONFIRMED_MESSAGE };
  if (res['error'] !== false || !isRecord(res['data']) || res['data']['success'] !== true) {
    const message = res['error'] === true ? friendlyGatewayError(String(res['message'] ?? '')) : UNCONFIRMED_MESSAGE;
    return { ok: false, message };
  }
  return { ok: true, data: res['data'] as unknown as T };
}

const CONSTRAINT_MESSAGES: ReadonlyArray<[RegExp, string]> = [
  [/uq_agri_plantations_code_active/i, 'Ya existe una plantación activa con esa clave en esta empresa.'],
  [/uq_agri_lots_code_active/i, 'Ya existe un lote activo con esa clave en esta plantación.'],
  [/uq_agri_rows_number_active/i, 'Ya existe una fila activa con ese número en este lote.'],
  [/uq_agri_plantations_default_active/i, 'Ya hay otra plantación predeterminada; vuelve a cargar la lista.'],
  [/lessor_only_if_rented/i, 'El arrendador solo se captura cuando la tenencia es Rentada.'],
  [/coordinates_pair/i, 'Captura latitud y longitud juntas, o deja ambas vacías.'],
  [/latitude_check/i, 'La latitud debe estar entre -90 y 90.'],
  [/longitude_check/i, 'La longitud debe estar entre -180 y 180.'],
  [/area_check/i, 'La superficie debe ser mayor que 0.'],
  [/alive_within_positions/i, 'Las plantas vivas no pueden superar los puntos de plantación.'],
  // Expenses (migration 081)
  [/uq_agri_expense_categories_code_active/i, 'Ya existe una categoría activa con esa clave.'],
  [/uq_agri_expense_categories_name_active/i, 'Ya existe una categoría activa con ese nombre.'],
  [/agri_expense_categories_code_format/i, 'La clave solo admite letras sin acento, números y guion bajo.'],
  [/invalid input syntax for type numeric/i, 'El monto o la cantidad no tienen un formato numérico válido.'],
  [/invalid input syntax for type (uuid|date)/i, 'Uno de los datos enviados no es válido. Vuelve a cargar la pantalla e inténtalo de nuevo.'],
];

/** Constraint / technical messages become Spanish; procedure messages (already Spanish) pass through. */
export function friendlyGatewayError(message: string, fallback = 'El servidor reportó un error al procesar la solicitud.'): string {
  const text = (message ?? '').trim();
  if (!text) return fallback;
  for (const [pattern, friendly] of CONSTRAINT_MESSAGES) {
    if (pattern.test(text)) return friendly;
  }
  return text;
}

// ---------------------------------------------------------------------------------------------------
// Form validation (mirrors 080)
// ---------------------------------------------------------------------------------------------------

const MAX_ROWS_PER_CALL = 500;
const MAX_POSITIONS = 10000;

const isWholeNumber = (text: string): boolean => /^\d+$/.test(text.trim());

/** Decimal text -> number; '' -> null; anything else -> NaN. Accepts a comma as decimal separator. */
export function parseDecimal(text: string | null | undefined): number | null {
  const value = (text ?? '').trim().replace(',', '.');
  if (value === '') return null;
  return /^-?\d+(\.\d+)?$/.test(value) ? Number(value) : NaN;
}

export function validateRowRange(from: string, to: string, positions: string): string | null {
  if (!isWholeNumber(from) || !isWholeNumber(to)) return 'Captura la fila inicial y la final como números enteros.';
  const a = Number(from);
  const b = Number(to);
  if (a < 1) return 'La fila inicial debe ser 1 o mayor.';
  if (b < a) return 'La fila final no puede ser menor que la inicial.';
  if (b - a + 1 > MAX_ROWS_PER_CALL) return `Máximo ${MAX_ROWS_PER_CALL} filas por alta (pediste ${b - a + 1}).`;
  if (!isWholeNumber(positions) || Number(positions) > MAX_POSITIONS) {
    return `Los puntos de plantación por fila deben ser un entero entre 0 y ${MAX_POSITIONS}.`;
  }
  return null;
}

export interface CensusFormCheck {
  alive: string;
  positions: string;
  currentPositions: number;
  reason: CensusReason | '';
  censusDate: string;
  today: string;
  canChangePositions: boolean;
}

/** Validates against the FINAL values, like sp_agri_record_row_census. */
export function validateCensus(form: CensusFormCheck): string | null {
  if (!form.reason) return 'Elige el motivo del conteo.';
  if (!isWholeNumber(form.alive)) return 'Captura las plantas vivas como número entero.';
  const positionsText = form.positions.trim();
  let finalPositions = form.currentPositions;
  if (positionsText !== '') {
    if (!isWholeNumber(positionsText) || Number(positionsText) > MAX_POSITIONS) {
      return `Los puntos de plantación deben ser un entero entre 0 y ${MAX_POSITIONS}.`;
    }
    finalPositions = Number(positionsText);
    if (finalPositions !== form.currentPositions && !form.canChangePositions) {
      return 'Solo un administrador de la empresa puede cambiar los puntos de plantación.';
    }
  }
  if (Number(form.alive) > finalPositions) {
    return `Las plantas vivas (${form.alive}) no pueden superar los ${finalPositions} puntos de plantación.`;
  }
  if (form.censusDate && form.censusDate > form.today) return 'La fecha del conteo no puede ser futura.';
  return null;
}

export function validatePlantationInput(input: PlantationInput): string | null {
  if (!input.code.trim()) return 'La clave de la plantación es obligatoria.';
  if (input.code.trim().length > 40) return 'La clave no puede exceder 40 caracteres.';
  if (!input.name.trim()) return 'El nombre de la plantación es obligatorio.';
  const area = parseDecimal(input.totalAreaHa);
  if (area === null || Number.isNaN(area) || area <= 0) return 'La superficie total (ha) debe ser un número mayor que 0.';
  const lat = parseDecimal(input.latitude);
  const lon = parseDecimal(input.longitude);
  if (Number.isNaN(lat) || Number.isNaN(lon)) return 'Latitud y longitud deben ser números.';
  if ((lat === null) !== (lon === null)) return 'Captura latitud y longitud juntas, o deja ambas vacías.';
  if (lat !== null && (lat < -90 || lat > 90)) return 'La latitud debe estar entre -90 y 90.';
  if (lon !== null && (lon < -180 || lon > 180)) return 'La longitud debe estar entre -180 y 180.';
  if (!input.tenure) return 'La tenencia es obligatoria.';
  if (input.tenure === 'RENTADA' && !input.lessorName.trim()) return 'El arrendador es obligatorio cuando la tenencia es Rentada.';
  return null;
}

export function validateLotInput(input: LotInput, today: string): string | null {
  if (!input.code.trim()) return 'La clave del lote es obligatoria.';
  if (input.code.trim().length > 40) return 'La clave no puede exceder 40 caracteres.';
  const area = parseDecimal(input.areaHa);
  if (area === null || Number.isNaN(area) || area <= 0) return 'La superficie del lote (ha) debe ser un número mayor que 0.';
  if (input.plantingDate && input.plantingDate > today) return 'La fecha de siembra no puede ser futura.';
  const spacing = parseDecimal(input.spacingM);
  if (Number.isNaN(spacing) || (spacing !== null && spacing <= 0)) return 'El espaciamiento debe ser un número mayor que 0.';
  if (input.designDensityPlantsHa.trim() !== '' && (!isWholeNumber(input.designDensityPlantsHa) || Number(input.designDensityPlantsHa) <= 0)) {
    return 'La densidad de diseño debe ser un entero mayor que 0.';
  }
  if (input.tenure === 'RENTADA' && !input.lessorName.trim()) return 'El arrendador es obligatorio cuando la tenencia del lote es Rentada.';
  return null;
}

/** Plantation form -> gateway fields (never id, id_company, is_default). */
export function buildPlantationFields(input: PlantationInput): Record<string, unknown> {
  return {
    plantation_code: input.code.trim(),
    plantation_name: input.name.trim(),
    state: blankToNull(input.state),
    municipality: blankToNull(input.municipality),
    locality: blankToNull(input.locality),
    latitude: parseDecimal(input.latitude),
    longitude: parseDecimal(input.longitude),
    total_area_ha: parseDecimal(input.totalAreaHa),
    tenure: input.tenure,
    lessor_name: input.tenure === 'RENTADA' ? blankToNull(input.lessorName) : null,
    notes: blankToNull(input.notes),
  };
}

/** Lot form -> gateway fields. tenure '' = inherited (NULL, and then the lessor must be NULL too). */
export function buildLotFields(input: LotInput): Record<string, unknown> {
  const tenure = input.tenure || null;
  return {
    lot_code: input.code.trim(),
    lot_name: blankToNull(input.name),
    area_ha: parseDecimal(input.areaHa),
    planting_date: blankToNull(input.plantingDate),
    planting_date_is_approx: !!input.plantingDateIsApprox,
    variety_id: blankToNull(input.varietyId),
    seed_supplier: blankToNull(input.seedSupplier),
    planting_pattern: input.plantingPattern || null,
    spacing_m: parseDecimal(input.spacingM),
    design_density_plants_ha: input.designDensityPlantsHa.trim() === '' ? null : Number(input.designDensityPlantsHa),
    water_regime: input.waterRegime || null,
    soil_type: blankToNull(input.soilType),
    tenure,
    lessor_name: tenure === 'RENTADA' ? blankToNull(input.lessorName) : null,
    notes: blankToNull(input.notes),
  };
}

/** Today in America/Mexico_City as YYYY-MM-DD (same "today" the database uses). */
export function todayCdmx(now: Date = new Date()): string {
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Mexico_City', year: 'numeric', month: '2-digit', day: '2-digit' })
    .format(now);
}
