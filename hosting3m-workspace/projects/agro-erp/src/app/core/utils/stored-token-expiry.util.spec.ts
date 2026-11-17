import { jwtDecode } from 'jwt-decode';
import { isPastGraceWindow, graceMsOf, readStoredTokenExpiry } from './stored-token-expiry.util';

/** Builds an unsigned JWT-shaped token; only the payload is read on the client. */
function tokenWith(payload: Record<string, unknown>): string {
  const enc = (o: unknown) => btoa(JSON.stringify(o)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  return `${enc({ alg: 'HS256', typ: 'JWT' })}.${enc(payload)}.sig`;
}

describe('stored-token-expiry util', () => {
  beforeEach(() => localStorage.clear());
  afterEach(() => { vi.useRealTimers(); localStorage.clear(); });

  describe('readStoredTokenExpiry', () => {
    it('reports none when there is no token', () => {
      expect(readStoredTokenExpiry()).toEqual({ kind: 'none' });
    });

    it('reports none for an empty stored value', () => {
      localStorage.setItem('authToken', '');
      expect(readStoredTokenExpiry()).toEqual({ kind: 'none' });
    });

    it('reports unreadable for a malformed token (fail-closed)', () => {
      localStorage.setItem('authToken', 'not-a-jwt');
      expect(readStoredTokenExpiry()).toEqual({ kind: 'unreadable', raw: 'not-a-jwt' });
    });

    it('reports unreadable when exp is missing or not a finite number', () => {
      const noExp = tokenWith({ user: 'ana' });
      localStorage.setItem('authToken', noExp);
      expect(readStoredTokenExpiry()).toEqual({ kind: 'unreadable', raw: noExp });
      const badExp = tokenWith({ user: 'ana', exp: 'soon' });
      localStorage.setItem('authToken', badExp);
      expect(readStoredTokenExpiry()).toEqual({ kind: 'unreadable', raw: badExp });
    });

    it('returns the exp and the raw token for a readable token, without claims', () => {
      const token = tokenWith({ user: 'ana', id_company: 1, exp: 1_700_000_000 });
      localStorage.setItem('authToken', token);
      expect(readStoredTokenExpiry()).toEqual({ kind: 'expiry', token, exp: 1_700_000_000 });
    });

    it('reports unreadable when localStorage throws', () => {
      vi.spyOn(Storage.prototype, 'getItem').mockImplementation(() => { throw new Error('denied'); });
      expect(readStoredTokenExpiry()).toEqual({ kind: 'unreadable', raw: null });
    });
  });

  describe('isPastGraceWindow boundary (T1)', () => {
    const EXP = 1_700_000_000;
    const at = (ms: number) => EXP * 1000 + ms;

    it('without grace: valid up to the exp second, expired one second after it', () => {
      expect(isPastGraceWindow(EXP, at(0), 0)).toBe(false);
      expect(isPastGraceWindow(EXP, at(999), 0)).toBe(false);
      expect(isPastGraceWindow(EXP, at(1000), 0)).toBe(true);
    });

    it('with a 1 h grace: not past at exactly exp + grace, past one second later', () => {
      const grace = 3_600_000;
      expect(isPastGraceWindow(EXP, at(grace - 1), grace)).toBe(false);
      expect(isPastGraceWindow(EXP, at(grace), grace)).toBe(false);
      expect(isPastGraceWindow(EXP, at(grace + 1000), grace)).toBe(true);
    });

    it('never reports a still-valid token (exp in the future) as past', () => {
      expect(isPastGraceWindow(EXP, at(-60_000), 0)).toBe(false);
    });
  });

  describe('graceMsOf', () => {
    it('is 0 when grace is not configured (production)', () => {
      expect(graceMsOf({})).toBe(0);
      expect(graceMsOf(null)).toBe(0);
    });

    it('returns the configured grace only when it is a positive finite number', () => {
      expect(graceMsOf({ offlineGraceMs: 3_600_000 })).toBe(3_600_000);
      expect(graceMsOf({ offlineGraceMs: 0 })).toBe(0);
      expect(graceMsOf({ offlineGraceMs: -5 })).toBe(0);
      expect(graceMsOf({ offlineGraceMs: Number.NaN })).toBe(0);
    });
  });

  it('keeps jwtDecode as the only decoder (sanity check of the fixture)', () => {
    expect(jwtDecode<{ exp: number }>(tokenWith({ exp: 5 })).exp).toBe(5);
  });
});
