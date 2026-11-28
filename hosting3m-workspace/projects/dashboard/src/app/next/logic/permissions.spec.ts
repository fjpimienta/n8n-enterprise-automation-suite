import { describe, expect, it } from 'vitest';
import { NextAction, ROLE_ACTIONS, can, normalizeRole } from './permissions';

const ACTIONS: NextAction[] = ['resolveTicket', 'finishCleaning', 'viewRepairCost'];
const allowed = (role: unknown) => ACTIONS.filter(a => can(role, a));

describe('permissions table', () => {
  it('ADMIN does everything; EDITOR only marks rooms clean', () => {
    expect(allowed('ADMIN')).toEqual(['resolveTicket', 'finishCleaning', 'viewRepairCost']);
    expect(allowed('EDITOR')).toEqual(['finishCleaning']);
  });
  it('roles without a row can do nothing (CUSTOMER, unknown)', () => {
    expect(allowed('CUSTOMER')).toEqual([]);
    expect(allowed('MAINTENANCE')).toEqual([]);
  });
  it('is case- and space-insensitive', () => {
    expect(can(' admin ', 'resolveTicket')).toBe(true);
    expect(can('Editor', 'finishCleaning')).toBe(true);
    expect(normalizeRole(' Editor ')).toBe('EDITOR');
  });
  it('fails closed for missing, empty, non-text and prototype-like roles', () => {
    for (const role of [null, undefined, '', '   ', 0, 1, {}, [], true, 'constructor', '__proto__', 'toString', 'hasOwnProperty']) {
      expect(allowed(role)).toEqual([]);
    }
  });
  it('adding a role is a data change: a new row grants exactly its actions', () => {
    const copy = new Map(ROLE_ACTIONS);
    copy.set('MAINTENANCE', new Set<NextAction>(['resolveTicket']));
    expect(copy.get('MAINTENANCE')!.has('resolveTicket')).toBe(true);
    expect(ROLE_ACTIONS.has('MAINTENANCE')).toBe(false); // the shipped table is unchanged
  });
  it('only ADMIN may see repair cost', () => {
    expect(['ADMIN', 'EDITOR', 'CUSTOMER', null].map(r => can(r, 'viewRepairCost'))).toEqual([true, false, false, false]);
  });
});
