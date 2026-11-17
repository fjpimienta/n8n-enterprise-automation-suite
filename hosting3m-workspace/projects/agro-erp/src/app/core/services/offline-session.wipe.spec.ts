import { TestBed } from '@angular/core/testing';
import { Router } from '@angular/router';
import { AuthService, SessionScope, SessionState } from 'core-auth';
import { OfflineSessionService } from './offline-session.service';
import { OfflineWipeEventsService } from './offline-wipe-events.service';

describe('OfflineSessionService on a wipe of the offline copy', () => {
  let state: SessionState;
  let scope: SessionScope | null;

  beforeEach(() => {
    state = 'grace';
    scope = { user: 'ana', id_company: 1 };
    TestBed.configureTestingModule({
      providers: [
        { provide: AuthService, useValue: { getSessionState: () => state, getSessionScope: () => scope } },
        { provide: Router, useValue: { url: '/', navigateByUrl: vi.fn() } }
      ]
    });
  });

  it('drops the PIN unlock of the wiped copy and re-reads the session state', () => {
    const service = TestBed.inject(OfflineSessionService);
    expect(service.unlock()).toBe(true);
    expect(service.unlocked()).toBe(true);

    state = 'expired';
    TestBed.inject(OfflineWipeEventsService).notifyWiped();

    expect(service.unlocked()).toBe(false);
    expect(service.state()).toBe('expired');
  });
});
