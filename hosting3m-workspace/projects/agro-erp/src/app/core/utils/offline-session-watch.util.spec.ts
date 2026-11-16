import { TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { Subject } from 'rxjs';
import { AUTH_ENV_CONFIG, AuthService, SessionEvent, TenantService } from 'core-auth';
import { OfflineSessionService } from '@core/services/offline-session.service';
import { OFFLINE_SESSION_CHECK_MS, startOfflineSessionWatch } from './offline-session-watch.util';

describe('startOfflineSessionWatch', () => {
  let session: { refresh: ReturnType<typeof vi.fn>; setOnline: ReturnType<typeof vi.fn> };
  let events: Subject<SessionEvent>;
  let graceMs: number | undefined;

  function start(): void {
    TestBed.resetTestingModule();
    session = { refresh: vi.fn(), setOnline: vi.fn() };
    events = new Subject<SessionEvent>();
    TestBed.configureTestingModule({
      providers: [
        provideRouter([]),
        { provide: AuthService, useValue: { sessionEvents$: events.asObservable() } },
        { provide: TenantService, useValue: { activeTenantChanges$: new Subject<void>().asObservable() } },
        { provide: OfflineSessionService, useValue: session },
        { provide: AUTH_ENV_CONFIG, useValue: { apiUrl_crud: '', apiUrl_token: '', apiUrl_ai: '', apiUrl_upload: '', system_id: 'test', offlineGraceMs: graceMs } },
      ],
    });
    TestBed.runInInjectionContext(() => startOfflineSessionWatch());
  }

  beforeEach(() => {
    vi.useFakeTimers();
    graceMs = undefined;
  });

  afterEach(() => {
    vi.useRealTimers();
    vi.restoreAllMocks();
  });

  describe('with offline grace disabled (production configuration)', () => {
    it('does no work: no 60 s timer, no refresh on time or on session events', () => {
      start();
      vi.advanceTimersByTime(OFFLINE_SESSION_CHECK_MS * 5);
      events.next({ type: 'login', scope: null });
      events.next({ type: 'logout' });
      document.dispatchEvent(new Event('visibilitychange'));
      window.dispatchEvent(new Event('online'));
      window.dispatchEvent(new Event('offline'));
      expect(session.refresh).not.toHaveBeenCalled();
      expect(session.setOnline).not.toHaveBeenCalled();
    });
  });

  describe('with offline grace configured', () => {
    beforeEach(() => {
      graceMs = 16 * 60 * 60 * 1000;
    });

    it('re-checks the session on the 60 s timer and on session events', () => {
      start();
      vi.advanceTimersByTime(OFFLINE_SESSION_CHECK_MS);
      expect(session.refresh).toHaveBeenCalledTimes(1);
      events.next({ type: 'logout' });
      expect(session.refresh).toHaveBeenCalledTimes(2);
    });
  });
});
