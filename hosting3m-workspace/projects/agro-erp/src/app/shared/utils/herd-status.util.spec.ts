import { describe, expect, it } from 'vitest';
import { uppCodeOf, unweightedHeads } from './herd-status.util';

describe('unweightedHeads', () => {
  it('counts missing, null, NaN, zero and negative weights, and parses string weights', () => {
    const list = [
      { current_weight_kg: null, production_unit_id: 'u1', upp_code: 'UPP-1' },
      { production_unit_id: 'u1', upp_code: 'UPP-1' },
      { current_weight_kg: '0', production_unit_id: 'u1', upp_code: 'UPP-1' },
      { current_weight_kg: 'abc', production_unit_id: 'u1', upp_code: 'UPP-1' },
      { current_weight_kg: -5, production_unit_id: 'u1', upp_code: 'UPP-1' },
      { current_weight_kg: NaN, production_unit_id: 'u1', upp_code: 'UPP-1' },
      { current_weight_kg: '450.5', production_unit_id: 'u1', upp_code: 'UPP-1' },
      { current_weight_kg: 300, production_unit_id: null },
    ];
    expect(unweightedHeads(list)).toEqual({ withoutWeight: 6, withoutWeightAndUpp: 0 });
  });

  it('counts the subset without production unit', () => {
    const list = [
      { current_weight_kg: null, production_unit_id: null },
      { current_weight_kg: '0' },
      { current_weight_kg: null, production_unit_id: 'u1', upp_code: 'UPP-1' },
      { current_weight_kg: 400, production_unit_id: null },
    ];
    expect(unweightedHeads(list)).toEqual({ withoutWeight: 3, withoutWeightAndUpp: 2 });
  });

  it('excludes animals out of the valued scope (deceased, sold)', () => {
    const list = [
      { current_status: 'BAJA_MORTANDAD', current_weight_kg: null },
      { current_status: 'VENDIDO', current_weight_kg: null },
      { current_status: 'ACTIVO', current_weight_kg: null },
    ];
    expect(unweightedHeads(list)).toEqual({ withoutWeight: 1, withoutWeightAndUpp: 1 });
  });

  it('returns zeros for an empty list', () => {
    expect(unweightedHeads([])).toEqual({ withoutWeight: 0, withoutWeightAndUpp: 0 });
  });
});

describe('uppCodeOf / "without UPP" criterion', () => {
  it('needs both a production unit and a non-blank code', () => {
    expect(uppCodeOf({ production_unit_id: 'u1', upp_code: ' UPP-1 ' })).toBe('UPP-1');
    expect(uppCodeOf({ production_unit_id: 'u1', upp_code: '' })).toBe('');
    expect(uppCodeOf({ production_unit_id: 'u1', upp_code: '  ' })).toBe('');
    expect(uppCodeOf({ production_unit_id: 'u1', upp_code: null })).toBe('');
    expect(uppCodeOf({ production_unit_id: null, upp_code: 'UPP-1' })).toBe('');
    expect(uppCodeOf(null)).toBe('');
  });

  it('counts an animal with production_unit_id but empty upp_code as without UPP', () => {
    const list = [{ current_weight_kg: null, production_unit_id: 'u1', upp_code: '' }];
    expect(unweightedHeads(list)).toEqual({ withoutWeight: 1, withoutWeightAndUpp: 1 });
  });
});
