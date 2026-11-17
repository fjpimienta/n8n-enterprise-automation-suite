import { TestBed } from '@angular/core/testing';
import { Subject } from 'rxjs';
import { AuthService, SessionEvent } from 'core-auth';
import { OfflineStoreService } from '@core/services/offline-store.service';
import { wireOfflineLogoutWipe } from './offline-logout-wipe.util';

describe('wireOfflineLogoutWipe', () => {
  let events: Subject<SessionEvent>;
  let wipeAll: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    events = new Subject<SessionEvent>();
    wipeAll = vi.fn().mockResolvedValue(true);
    TestBed.configureTestingModule({
      providers: [
        { provide: AuthService, useValue: { sessionEvents$: events.asObservable() } },
        { provide: OfflineStoreService, useValue: { wipeAll } }
      ]
    });
    TestBed.runInInjectionContext(() => wireOfflineLogoutWipe());
  });

  it('wipes the read cache on logout', () => {
    events.next({ type: 'logout' });
    expect(wipeAll).toHaveBeenCalledTimes(1);
  });

  it('does not wipe on login', () => {
    events.next({ type: 'login', scope: { user: 'a', id_company: 1 } });
    expect(wipeAll).not.toHaveBeenCalled();
  });

  it('wipes on every logout event, with no skip condition', () => {
    events.next({ type: 'logout' });
    events.next({ type: 'login', scope: { user: 'a', id_company: 1 } });
    events.next({ type: 'logout' });
    events.next({ type: 'logout' });
    expect(wipeAll).toHaveBeenCalledTimes(3);
  });

  it('never throws when wipeAll rejects or throws synchronously', () => {
    wipeAll.mockRejectedValueOnce(new Error('x'));
    expect(() => events.next({ type: 'logout' })).not.toThrow();
    wipeAll.mockImplementationOnce(() => { throw new Error('y'); });
    expect(() => events.next({ type: 'logout' })).not.toThrow();
  });
});
