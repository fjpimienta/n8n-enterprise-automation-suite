import { signal } from '@angular/core';
import { TestBed } from '@angular/core/testing';
import { Subject } from 'rxjs';
import { vi } from 'vitest';
import { AuthService, TenantService } from 'core-auth';
import { CattleApiService } from './cattle-api.service';
import { CattleDataService } from './cattle-data.service';
import { OfflineStoreService } from './offline-store.service';
import { OfflineWipeEventsService } from './offline-wipe-events.service';
import { LoggerService } from './logger.service';

/** The herd held in memory is cleared when the offline cache is wiped on expiry (D2, #1087 1b-iii-c). */
describe('CattleDataService reset on offline cache wipe', () => {
  it('clears the herd and the cache flags when the wipe event fires', async () => {
    const events = new Subject<{ type: string }>();
    const changes = new Subject<number | null>();
    const wiped = new OfflineWipeEventsService();
    TestBed.configureTestingModule({
      providers: [
        { provide: CattleApiService, useValue: { getAllLivestock: vi.fn().mockResolvedValue([{ id: 'a', tenant_id: 3 }]) } },
        { provide: TenantService, useValue: { activeTenantId: signal<number | null>(3).asReadonly(), activeTenantChanges$: changes.asObservable(), availableTenants: () => [{ id_company: 3 }] } },
        { provide: AuthService, useValue: { sessionEvents$: events.asObservable(), getSessionScope: () => ({ user: 'ana', id_company: 3 }), getSessionState: () => 'valid' } },
        { provide: OfflineStoreService, useValue: { get: vi.fn().mockResolvedValue(null), put: vi.fn().mockResolvedValue(true) } },
        { provide: LoggerService, useValue: { warn: vi.fn(), error: vi.fn(), info: vi.fn() } },
        { provide: OfflineWipeEventsService, useValue: wiped }
      ]
    });
    vi.spyOn(console, 'error').mockImplementation(() => undefined);
    const svc = TestBed.inject(CattleDataService);
    TestBed.flushEffects();
    await new Promise(resolve => setTimeout(resolve, 0));
    expect(svc.cattleList().length).toBe(1);
    expect(svc.hasLoadedOnce()).toBe(true);

    wiped.notifyWiped();

    expect(svc.cattleList()).toEqual([]);
    expect(svc.hasLoadedOnce()).toBe(false);
    expect(svc.servedFromCache()).toBe(false);
    expect(svc.cacheSavedAt()).toBeNull();
  });
});
