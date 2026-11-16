import { TestBed } from '@angular/core/testing';
import { ActivatedRouteSnapshot, Router, RouterStateSnapshot, UrlTree, provideRouter } from '@angular/router';
import { AUTH_ENV_CONFIG, AuthService, SessionScope, SessionState, TenantService } from 'core-auth';
import { OfflineSessionService } from '@core/services/offline-session.service';
import { notInGraceGuard, offlineSessionGuard, pinSetupRouteGuard, unlockRouteGuard } from './offline-session.guard';

const route = {} as ActivatedRouteSnapshot;
const snapshot = {} as RouterStateSnapshot;

describe('offline session guards', () => {
  let state: SessionState;
  let authed: boolean;
  let scope: SessionScope | null;
  /** Shared config object: the grace-off case flips `offlineGraceMs` before the service is created. */
  const authConfig = { apiUrl_crud: '', apiUrl_token: '', apiUrl_ai: '', apiUrl_upload: '', system_id: 'test', offlineGraceMs: 16 * 60 * 60 * 1000 as number | undefined };

  beforeEach(() => {
    state = 'valid';
    authed = true;
    scope = { user: 'ana', id_company: 1 };
    authConfig.offlineGraceMs = 16 * 60 * 60 * 1000;
    TestBed.resetTestingModule();
    TestBed.configureTestingModule({
      providers: [
        provideRouter([{ path: 'login', children: [] }, { path: 'unlock', children: [] }, { path: '', children: [] }]),
        {
          provide: AuthService,
          useValue: {
            isAuthenticated: () => authed,
            getSessionState: () => state,
            getSessionScope: () => scope,
            sessionEvents$: { subscribe: () => ({ unsubscribe() {} }) },
          },
        },
        { provide: TenantService, useValue: { activeTenant: () => ({ industry: 'Ganadería', business_type: 'LIVESTOCK' }) } },
        { provide: AUTH_ENV_CONFIG, useValue: authConfig },
      ],
    });
  });

  const run = (guard: (...args: never[]) => unknown) =>
    TestBed.runInInjectionContext(() => (guard as (r: ActivatedRouteSnapshot, s: RouterStateSnapshot) => unknown)(route, snapshot));

  describe('offlineSessionGuard', () => {
    it('valid: behaves exactly like core-auth authGuard (allowed when authenticated)', () => {
      expect(run(offlineSessionGuard)).toBe(true);
    });

    it('expired: behaves exactly like core-auth authGuard (sent to login)', () => {
      state = 'expired';
      authed = false;
      expect(run(offlineSessionGuard)).toBe(false);
    });

    it('grace and locked: redirects to the unlock screen', () => {
      state = 'grace';
      const result = run(offlineSessionGuard) as UrlTree;
      expect(String(result)).toBe('/unlock');
    });

    it('grace and unlocked for this scope: allowed', () => {
      state = 'grace';
      TestBed.inject(OfflineSessionService).unlock();
      expect(run(offlineSessionGuard)).toBe(true);
    });

    it('grace unlocked for another scope is locked again', () => {
      state = 'grace';
      TestBed.inject(OfflineSessionService).unlock();
      scope = { user: 'ana', id_company: 2 };
      expect(String(run(offlineSessionGuard))).toBe('/unlock');
    });
  });

  describe('unlockRouteGuard', () => {
    it('allows the unlock screen only while grace is locked', () => {
      state = 'grace';
      expect(run(unlockRouteGuard)).toBe(true);
      TestBed.inject(OfflineSessionService).unlock();
      expect(String(run(unlockRouteGuard))).toBe('/');
    });

    it('sends valid and expired sessions home', () => {
      expect(String(run(unlockRouteGuard))).toBe('/');
      state = 'expired';
      expect(String(run(unlockRouteGuard))).toBe('/');
    });
  });

  describe('pinSetupRouteGuard', () => {
    it('allows PIN setup only in a valid session (grace configured)', () => {
      expect(run(pinSetupRouteGuard)).toBe(true);
      state = 'grace';
      expect(String(run(pinSetupRouteGuard))).toBe('/');
    });

    it('redirects to / with grace NOT configured (production), even for a valid online session', () => {
      authConfig.offlineGraceMs = undefined;
      state = 'valid';
      expect(String(run(pinSetupRouteGuard))).toBe('/');
    });

    it('redirects to / with grace not configured, whatever the session state', () => {
      authConfig.offlineGraceMs = undefined;
      for (const s of ['valid', 'grace', 'expired'] as const) {
        state = s;
        expect(String(run(pinSetupRouteGuard))).toBe('/');
      }
    });
  });

  describe('notInGraceGuard (admin screens)', () => {
    it('allows admin screens in a valid session', () => {
      expect(run(notInGraceGuard)).toBe(true);
    });

    it('denies admin screens in grace, even after unlock, and sends the user to the domain dashboard', () => {
      state = 'grace';
      TestBed.inject(OfflineSessionService).unlock();
      expect(String(run(notInGraceGuard))).toBe('/ganaderia/dashboard');
    });
  });

  it('keeps the router injectable for the guards', () => {
    expect(TestBed.inject(Router)).toBeTruthy();
  });
});
