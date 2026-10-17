/**
 * Display-only aggregations of the palm dashboard (nothing is persisted; the per-lot figures come from
 * vw_agri_lot_summary). Only ACTIVE lots are counted.
 */
import { LotSummary, ProductiveStage, STAGE_OPTIONS } from '@core/models/agri.model';

export interface StageBucket {
  stage: ProductiveStage;
  label: string;
  range: string;
  badge: string;
  lots: number;
  areaHa: number;
}

/** One bucket per stage, in the canonical order (empty stages included, so the chart never jumps). */
export function lotsByStage(lots: readonly LotSummary[]): StageBucket[] {
  const active = lots.filter(l => l.isActive);
  return STAGE_OPTIONS.map(s => {
    const inStage = active.filter(l => l.productiveStage === s.value);
    return {
      stage: s.value, label: s.label, range: s.range, badge: s.badge,
      lots: inStage.length,
      areaHa: round(inStage.reduce((sum, l) => sum + l.areaHa, 0), 2),
    };
  });
}

export interface PlantTotals {
  plantingPositions: number;
  alivePlants: number;
  missingPlants: number;
  /** % of planting positions that are missing; null when there are no positions. */
  missingPct: number | null;
}

export function plantTotals(lots: readonly LotSummary[]): PlantTotals {
  const active = lots.filter(l => l.isActive);
  const plantingPositions = active.reduce((s, l) => s + l.plantingPositions, 0);
  const alivePlants = active.reduce((s, l) => s + l.alivePlants, 0);
  const missingPlants = active.reduce((s, l) => s + l.missingPlants, 0);
  return {
    plantingPositions, alivePlants, missingPlants,
    missingPct: plantingPositions > 0 ? round((100 * missingPlants) / plantingPositions, 1) : null,
  };
}

export interface DensityComparison {
  /** Alive plants per hectare over the lots that declare a design density. */
  realPlantsHa: number | null;
  /** Area-weighted design density of those same lots. */
  designPlantsHa: number | null;
  pctOfDesign: number | null;
  lotsCompared: number;
}

/** Real vs. design density over the active lots that have a design density (same set on both sides). */
export function densityComparison(lots: readonly LotSummary[]): DensityComparison {
  const comparable = lots.filter(l => l.isActive && l.areaHa > 0 && (l.designDensityPlantsHa ?? 0) > 0);
  const area = comparable.reduce((s, l) => s + l.areaHa, 0);
  if (area <= 0) return { realPlantsHa: null, designPlantsHa: null, pctOfDesign: null, lotsCompared: 0 };
  const alive = comparable.reduce((s, l) => s + l.alivePlants, 0);
  const designPlants = comparable.reduce((s, l) => s + (l.designDensityPlantsHa ?? 0) * l.areaHa, 0);
  const real = alive / area;
  const design = designPlants / area;
  return {
    realPlantsHa: round(real, 1), designPlantsHa: round(design, 1),
    pctOfDesign: design > 0 ? round((100 * real) / design, 1) : null,
    lotsCompared: comparable.length,
  };
}

function round(value: number, digits: number): number {
  const f = 10 ** digits;
  return Math.round(value * f) / f;
}
