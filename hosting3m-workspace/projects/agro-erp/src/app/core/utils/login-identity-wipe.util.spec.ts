import { TestBed } from '@angular/core/testing';
import { Subject } from 'rxjs';
import { AUTH_ENV_CONFIG, AuthService, SessionEvent } from 'core-auth';
import { OfflineStoreService } from '@core/services/offline-store.service';
import { PinLockService } from '@core/services/pin-lock.service';
import { LoginHandoffService } from '@core/services/login-handoff.service';
import { wireLoginIdentityWipe } from './login-identity-wipe.util';

function b64url(obj: unknown): string {
  return btoa(JSON.stringify(obj)).replace(/=+$/, '').replace(/\+/g, '-').replace(/\//g, '_');
}
const tokenFor = (user: string) => `${b64url({ alg: 'HS256', typ: 'JWT' })}.${b64url({ user, exp: 9e9 })}.sig`;

describe('wireLoginIdentityWipe', () => {
  let events: Subject<SessionEvent>;
  let store: { wipeAll: ReturnType<typeof vi.fn> };
  let pinLock: { deleteOthers: ReturnType<typeof vi.fn> };
  let handoff: LoginHandoffService;
  /** Flipped by the grace-off case; the wiring reads it when an event arrives. */
  const authConfig: { apiUrl_crud: string; apiUrl_token: string; apiUrl_ai: string; apiUrl_upload: string; system_id: string; offlineGraceMs?: number } = {
    apiUrl_crud: '', apiUrl_token: '', apiUrl_ai: '', apiUrl_upload: '', system_id: 'test', offlineGraceMs: 16 * 60 * 60 * 1000,
  };

  beforeEach(() => {
    localStorage.clear();
    authConfig.offlineGraceMs = 16 * 60 * 60 * 1000;
    events = new Subject<SessionEvent>();
    store = { wipeAll: vi.fn(async () => true) };
    pinLock = { deleteOthers: vi.fn(async () => true) };
    TestBed.resetTestingModule();
    TestBed.configureTestingModule({
      providers: [
        { provide: AuthService, useValue: { sessionEvents$: events.asObservable() } },
        { provide: OfflineStoreService, useValue: store },
        { provide: PinLockService, useValue: pinLock },
        { provide: AUTH_ENV_CONFIG, useValue: authConfig },
      ],
    });
    handoff = TestBed.inject(LoginHandoffService);
    TestBed.runInInjectionContext(() => wireLoginIdentityWipe());
  });

  afterEach(() => localStorage.clear());

  /** A successful login: the login request captured `previous`, then the new token is stored. */
  function login(previous: string | null, next: string | null): void {
    handoff.begin(previous);
    if (next) localStorage.setItem('authToken', tokenFor(next));
    else localStorage.removeItem('authToken');
    events.next({ type: 'login', scope: null });
  }

  it('the SAME user keeps the cache and the PIN records', () => {
    login('ana', 'ana');
    expect(store.wipeAll).not.toHaveBeenCalled();
    expect(pinLock.deleteOthers).not.toHaveBeenCalled();
  });

  it('a DIFFERENT user wipes the cache and deletes the other users\' PIN records', () => {
    login('ana', 'beto');
    expect(store.wipeAll).toHaveBeenCalledTimes(1);
    expect(pinLock.deleteOthers).toHaveBeenCalledWith('beto');
  });

  it('an unknown previous user wipes (fail-closed), even if the new user matches', () => {
    login(null, 'ana');
    expect(store.wipeAll).toHaveBeenCalledTimes(1);
    expect(pinLock.deleteOthers).toHaveBeenCalledWith('ana');
  });

  it('a login with no captured login request wipes (fail-closed)', () => {
    localStorage.setItem('authToken', tokenFor('ana'));
    events.next({ type: 'login', scope: null });
    expect(store.wipeAll).toHaveBeenCalledTimes(1);
  });

  it('a new token without an identity claim wipes and keeps no PIN record', () => {
    login('ana', null);
    expect(store.wipeAll).toHaveBeenCalledTimes(1);
    expect(pinLock.deleteOthers).toHaveBeenCalledWith(null);
  });

  it('a FAILED login emits no login event: cache and PIN stay intact, and a later same-user login keeps them', () => {
    handoff.begin('ana'); // POST sent, then rejected: no token change, no event
    expect(store.wipeAll).not.toHaveBeenCalled();
    expect(pinLock.deleteOthers).not.toHaveBeenCalled();
    login('ana', 'ana');
    expect(store.wipeAll).not.toHaveBeenCalled();
  });

  it('logout events are not handled here (the logout wipe owns them)', () => {
    events.next({ type: 'logout' });
    expect(store.wipeAll).not.toHaveBeenCalled();
    expect(pinLock.deleteOthers).not.toHaveBeenCalled();
  });

  it('without offlineGraceMs (production): the offline cache is still wiped on a different user, but the PIN database is never touched', () => {
    authConfig.offlineGraceMs = undefined;
    login('ana', 'luis');
    expect(store.wipeAll).toHaveBeenCalledTimes(1);
    expect(pinLock.deleteOthers).not.toHaveBeenCalled();
  });
});
