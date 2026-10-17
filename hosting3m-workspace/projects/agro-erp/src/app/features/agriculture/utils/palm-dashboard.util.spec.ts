import { describe, expect, it } from 'vitest';
import type { LotSummary } from '@core/models/agri.model';
import { densityComparison, lotsByStage, plantTotals } from './palm-dashboard.util';

const lot = (o: Partial<LotSummary>): LotSummary => ({
  id: 'x', idCompany: 10, plantationId: 'p', code: 'L', name: null, isActive: true, areaHa: 10,
  plantingDate: null, plantingDateIsApprox: false, varietyName: null, effectiveTenure: 'PROPIA', effectiveLessorName: null,
  ageYears: null, productiveStage: 'SIN_FECHA', activeRows: 0, plantingPositions: 0, alivePlants: 0, missingPlants: 0,
  realDensityPlantsHa: null, designDensityPlantsHa: null, densityPctOfDesign: null, lastCensusDate: null, ...o,
});

describe('lotsByStage', () => {
  it('returns every stage in order, including PRODUCCION_DECLINANTE, and ignores inactive lots', () => {
    const buckets = lotsByStage([
      lot({ productiveStage: 'PRODUCCION_PLENA', areaHa: 25 }),
      lot({ productiveStage: 'PRODUCCION_PLENA', areaHa: 5.5 }),
      lot({ productiveStage: 'PRODUCCION_DECLINANTE', areaHa: 3 }),
      lot({ productiveStage: 'INMADURA', areaHa: 7, isActive: false }),
    ]);
    expect(buckets.map(b => b.stage)).toEqual(
      ['INMADURA', 'INICIO_PRODUCCION', 'PRODUCCION_PLENA', 'PRODUCCION_DECLINANTE', 'RENOVACION', 'SIN_FECHA']);
    expect(buckets.find(b => b.stage === 'PRODUCCION_PLENA')).toMatchObject({ lots: 2, areaHa: 30.5 });
    expect(buckets.find(b => b.stage === 'PRODUCCION_DECLINANTE')).toMatchObject({ lots: 1, areaHa: 3 });
    expect(buckets.find(b => b.stage === 'INMADURA')).toMatchObject({ lots: 0, areaHa: 0 });
  });
});

describe('plantTotals', () => {
  it('adds active lots only and computes the missing percentage', () => {
    const t = plantTotals([
      lot({ plantingPositions: 217, alivePlants: 213, missingPlants: 4 }),
      lot({ plantingPositions: 100, alivePlants: 0, missingPlants: 100, isActive: false }),
    ]);
    expect(t).toEqual({ plantingPositions: 217, alivePlants: 213, missingPlants: 4, missingPct: 1.8 });
  });
  it('no positions -> null percentage', () => {
    expect(plantTotals([]).missingPct).toBeNull();
  });
});

describe('densityComparison', () => {
  it('compares real vs. area-weighted design density over the same lots', () => {
    const d = densityComparison([
      lot({ areaHa: 20, alivePlants: 2800, designDensityPlantsHa: 143 }),
      lot({ areaHa: 10, alivePlants: 1300, designDensityPlantsHa: 136 }),
      lot({ areaHa: 50, alivePlants: 9999 }), // no design density: excluded from both sides
    ]);
    expect(d.lotsCompared).toBe(2);
    expect(d.realPlantsHa).toBe(136.7);   // 4100 / 30
    expect(d.designPlantsHa).toBe(140.7); // (143*20 + 136*10) / 30
    expect(d.pctOfDesign).toBe(97.2);
  });
  it('nothing comparable -> nulls', () => {
    expect(densityComparison([lot({ designDensityPlantsHa: null })]))
      .toEqual({ realPlantsHa: null, designPlantsHa: null, pctOfDesign: null, lotsCompared: 0 });
  });
});
