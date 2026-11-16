import { TestBed } from '@angular/core/testing';
import { Router, provideRouter } from '@angular/router';
import { Subject } from 'rxjs';
import { AuthService, SessionScope, SessionState, TenantService } from 'core-auth';
import { OfflineSessionService, UNLOCK_ROUTE, isSameScope } from './offline-session.service';
import { OFFLINE_SESSION_CHECK_MS, startOfflineSessionWatch } from '@core/utils/offline-session-watch.util';

describe('OfflineSessionService', () => {
  let state: SessionState;
  let scope: SessionScope | null;
  let auth: { getSessionState: () => SessionState; getSessionScope: () => SessionScope | null;
    getStoredToken: ReturnType<typeof vi.fn>; sessionEvents$: Subject<unknown> };
  let router: Router;
  let navigate: ReturnType<typeof vi.spyOn>;

  beforeEach(() => {
    state = 'valid';
    scope = { user: 'ana', id_company: 1 };
    auth = {
      getSessionState: () => state,
      getSessionScope: () => scope,
      // Must never be called by the session watch: it logs out on an expired token.
      getStoredToken: vi.fn(() => { throw new Error('getStoredToken must not be called'); }),
      sessionEvents$: new Subject(),
    };
    TestBed.resetTestingModule();
    TestBed.configureTestingModule({
      providers: [
        provideRouter([{ path: 'unlock', children: [] }, { path: 'login', children: [] }, { path: '', children: [] }]),
        { provide: AuthService, useValue: auth },
      ],
    });
    router = TestBed.inject(Router);
    navigate = vi.spyOn(router, 'navigateByUrl').mockResolvedValue(true);
  });

  afterEach(() => vi.restoreAllMocks());

  it('is not locked in a valid session and never navigates', () => {
    const svc = TestBed.inject(OfflineSessionService);
    svc.refresh();
    expect(svc.locked()).toBe(false);
    expect(navigate).not.toHaveBeenCalled();
  });

  it('a cold start in grace is locked but does not redirect itself (the guards do)', () => {
    state = 'grace';
    const svc = TestBed.inject(OfflineSessionService);
    expect(svc.locked()).toBe(true);
    expect(navigate).not.toHaveBeenCalled();
  });

  it('entering grace while open re-locks and redirects to the unlock screen', () => {
    const svc = TestBed.inject(OfflineSessionService);
    state = 'grace';
    svc.refresh();
    expect(svc.locked()).toBe(true);
    expect(navigate).toHaveBeenCalledWith(UNLOCK_ROUTE);
  });

  it('does not redirect away from /login or /unlock', () => {
    const svc = TestBed.inject(OfflineSessionService);
    vi.spyOn(router, 'url', 'get').mockReturnValue('/login');
    state = 'grace';
    svc.refresh();
    expect(navigate).not.toHaveBeenCalled();
  });

  it('unlock is granted only in grace with a scope, and is refused otherwise', () => {
    const svc = TestBed.inject(OfflineSessionService);
    expect(svc.unlock()).toBe(false);
    state = 'grace';
    scope = null;
    expect(svc.unlock()).toBe(false);
    scope = { user: 'ana', id_company: 1 };
    expect(svc.unlock()).toBe(true);
    expect(svc.unlocked()).toBe(true);
    expect(svc.locked()).toBe(false);
  });

  it('a tenant switch after unlock re-locks and requires a new unlock', () => {
    state = 'grace';
    const svc = TestBed.inject(OfflineSessionService);
    svc.unlock();
    scope = { user: 'ana', id_company: 2 };
    svc.refresh();
    expect(svc.locked()).toBe(true);
    expect(navigate).toHaveBeenCalledWith(UNLOCK_ROUTE);
  });

  it('a session that goes valid and then grace again needs a new unlock', () => {
    state = 'grace';
    const svc = TestBed.inject(OfflineSessionService);
    svc.unlock();
    state = 'valid';
    svc.refresh();
    state = 'grace';
    svc.refresh();
    expect(svc.locked()).toBe(true);
  });

  it('a new instance in grace asks again (unlock is memory only)', () => {
    state = 'grace';
    TestBed.inject(OfflineSessionService).unlock();
    TestBed.resetTestingModule();
    TestBed.configureTestingModule({
      providers: [provideRouter([]), { provide: AuthService, useValue: auth }],
    });
    expect(TestBed.inject(OfflineSessionService).locked()).toBe(true);
  });

  it('refresh and unlock never call getStoredToken (no logout, no HTTP path)', () => {
    state = 'grace';
    const svc = TestBed.inject(OfflineSessionService);
    svc.refresh();
    svc.unlock();
    svc.refresh();
    expect(auth.getStoredToken).not.toHaveBeenCalled();
  });

  it('isSameScope compares user and company', () => {
    expect(isSameScope({ user: 'a', id_company: 1 }, { user: 'a', id_company: 1 })).toBe(true);
    expect(isSameScope({ user: 'a', id_company: 1 }, { user: 'a', id_company: 2 })).toBe(false);
    expect(isSameScope(null, { user: 'a', id_company: 1 })).toBe(false);
  });
});

describe('startOfflineSessionWatch', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    TestBed.resetTestingModule();
    TestBed.configureTestingModule({
      providers: [
        provideRouter([]),
        { provide: AuthService, useValue: { getSessionState: () => 'valid', getSessionScope: () => null, sessionEvents$: new Subject() } },
        { provide: TenantService, useValue: { activeTenantChanges$: new Subject(), activeTenantId: () => null } },
      ],
    });
  });

  afterEach(() => {
    TestBed.resetTestingModule();
    vi.useRealTimers();
  });

  it('re-checks on the timer and on visibility changes, and stops when destroyed', () => {
    const session = TestBed.inject(OfflineSessionService);
    const refresh = vi.spyOn(session, 'refresh');
    TestBed.runInInjectionContext(() => startOfflineSessionWatch());

    vi.advanceTimersByTime(OFFLINE_SESSION_CHECK_MS);
    expect(refresh).toHaveBeenCalledTimes(1);

    document.dispatchEvent(new Event('visibilitychange'));
    expect(refresh).toHaveBeenCalledTimes(2);

    TestBed.resetTestingModule();
    vi.advanceTimersByTime(OFFLINE_SESSION_CHECK_MS * 3);
    expect(refresh).toHaveBeenCalledTimes(2);
  });
});
