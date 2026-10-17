/**
 * Palm structure (migration 080): company -> plantation -> lot -> row (plant count per row).
 *
 * The security boundary is id_company; the active plantation is only a UI scope filter. Fields that only
 * procedures may change (is_default, planting_positions, alive_plants, last_census_date) are read-only
 * here: plantations' default goes through `agri_set_default_plantation`, rows through
 * `agri_bulk_create_rows` and counts / positions through `agri_record_row_census`.
 */

export type PlantationTenure = 'PROPIA' | 'RENTADA' | 'EJIDAL' | 'COMODATO';
export type PlantingPattern = 'TRESBOLILLO' | 'CUADRO' | 'OTRO';
export type WaterRegime = 'TEMPORAL' | 'RIEGO';
export type CensusReason = 'CENSO' | 'RESIEMBRA' | 'PERDIDA' | 'CORRECCION_CAPTURA';
export type HistoryReason = CensusReason | 'ALTA';
export type ProductiveStage =
  | 'INMADURA' | 'INICIO_PRODUCCION' | 'PRODUCCION_PLENA' | 'PRODUCCION_DECLINANTE' | 'RENOVACION' | 'SIN_FECHA';

export const TENURE_OPTIONS: ReadonlyArray<{ value: PlantationTenure; label: string }> = [
  { value: 'PROPIA', label: 'Propia' },
  { value: 'RENTADA', label: 'Rentada' },
  { value: 'EJIDAL', label: 'Ejidal' },
  { value: 'COMODATO', label: 'Comodato' },
];

export const PLANTING_PATTERN_OPTIONS: ReadonlyArray<{ value: PlantingPattern; label: string }> = [
  { value: 'TRESBOLILLO', label: 'Tresbolillo' },
  { value: 'CUADRO', label: 'Cuadro' },
  { value: 'OTRO', label: 'Otro' },
];

export const WATER_REGIME_OPTIONS: ReadonlyArray<{ value: WaterRegime; label: string }> = [
  { value: 'TEMPORAL', label: 'Temporal' },
  { value: 'RIEGO', label: 'Riego' },
];

export const CENSUS_REASON_OPTIONS: ReadonlyArray<{ value: CensusReason; label: string }> = [
  { value: 'CENSO', label: 'Censo (conteo de rutina)' },
  { value: 'PERDIDA', label: 'Pérdida' },
  { value: 'RESIEMBRA', label: 'Resiembra' },
  { value: 'CORRECCION_CAPTURA', label: 'Corrección de captura' },
];

export const HISTORY_REASON_LABELS: Readonly<Record<HistoryReason, string>> = {
  ALTA: 'Alta de fila',
  CENSO: 'Censo',
  PERDIDA: 'Pérdida',
  RESIEMBRA: 'Resiembra',
  CORRECCION_CAPTURA: 'Corrección de captura',
};

/** ⚠️ Orientative cut-offs, pending confirmation with the client (see vw_agri_lot_summary). */
export const STAGE_OPTIONS: ReadonlyArray<{ value: ProductiveStage; label: string; range: string; badge: string }> = [
  { value: 'INMADURA', label: 'Inmadura', range: '< 3 años', badge: 'bg-azure-lt' },
  { value: 'INICIO_PRODUCCION', label: 'Inicio de producción', range: '3–7 años', badge: 'bg-lime-lt' },
  { value: 'PRODUCCION_PLENA', label: 'Producción plena', range: '8–20 años', badge: 'bg-green-lt' },
  { value: 'PRODUCCION_DECLINANTE', label: 'Producción declinante', range: '21–25 años', badge: 'bg-yellow-lt' },
  { value: 'RENOVACION', label: 'Renovación', range: '> 25 años', badge: 'bg-orange-lt' },
  { value: 'SIN_FECHA', label: 'Sin fecha de siembra', range: '—', badge: 'bg-secondary-lt' },
];

export interface Variety {
  id: string;
  code: string;
  name: string;
  isActive: boolean;
}

export interface Plantation {
  id: string;
  idCompany: number;
  code: string;
  name: string;
  state: string | null;
  municipality: string | null;
  locality: string | null;
  latitude: number | null;
  longitude: number | null;
  totalAreaHa: number;
  tenure: PlantationTenure;
  lessorName: string | null;
  isDefault: boolean;
  isActive: boolean;
  notes: string | null;
  createdAt: string;
}

export interface PlantationSummary {
  id: string;
  idCompany: number;
  code: string;
  name: string;
  isActive: boolean;
  isDefault: boolean;
  totalAreaHa: number;
  activeLots: number;
  plantedAreaHa: number;
  hasAreaInconsistency: boolean;
  activeRows: number;
  plantingPositions: number;
  alivePlants: number;
  missingPlants: number;
}

export interface Lot {
  id: string;
  idCompany: number;
  plantationId: string;
  code: string;
  name: string | null;
  areaHa: number;
  plantingDate: string | null;
  plantingDateIsApprox: boolean;
  varietyId: string | null;
  seedSupplier: string | null;
  plantingPattern: PlantingPattern | null;
  spacingM: number | null;
  designDensityPlantsHa: number | null;
  waterRegime: WaterRegime | null;
  soilType: string | null;
  /** NULL = same tenure as the plantation. */
  tenure: PlantationTenure | null;
  lessorName: string | null;
  isActive: boolean;
  notes: string | null;
}

export interface LotSummary {
  id: string;
  idCompany: number;
  plantationId: string;
  code: string;
  name: string | null;
  isActive: boolean;
  areaHa: number;
  plantingDate: string | null;
  plantingDateIsApprox: boolean;
  varietyName: string | null;
  effectiveTenure: PlantationTenure | null;
  effectiveLessorName: string | null;
  ageYears: number | null;
  productiveStage: ProductiveStage;
  activeRows: number;
  plantingPositions: number;
  alivePlants: number;
  missingPlants: number;
  realDensityPlantsHa: number | null;
  designDensityPlantsHa: number | null;
  densityPctOfDesign: number | null;
  lastCensusDate: string | null;
}

export interface AgriRow {
  id: string;
  idCompany: number;
  lotId: string;
  rowNumber: number;
  plantingPositions: number;
  alivePlants: number;
  lastCensusDate: string | null;
  isActive: boolean;
  notes: string | null;
}

export interface CensusHistoryEntry {
  id: string;
  rowId: string;
  previousPositions: number | null;
  newPositions: number;
  previousAlive: number | null;
  newAlive: number;
  reason: HistoryReason;
  changedBy: string | null;
  notes: string | null;
  changedAt: string;
}

export interface PlantationInput {
  code: string;
  name: string;
  state: string;
  municipality: string;
  locality: string;
  latitude: string;
  longitude: string;
  totalAreaHa: string;
  tenure: PlantationTenure;
  lessorName: string;
  notes: string;
}

export interface LotInput {
  code: string;
  name: string;
  areaHa: string;
  plantingDate: string;
  plantingDateIsApprox: boolean;
  varietyId: string;
  seedSupplier: string;
  plantingPattern: PlantingPattern | '';
  spacingM: string;
  designDensityPlantsHa: string;
  waterRegime: WaterRegime | '';
  soilType: string;
  /** '' = "Igual que la plantación" (sent as NULL). */
  tenure: PlantationTenure | '';
  lessorName: string;
  notes: string;
}
