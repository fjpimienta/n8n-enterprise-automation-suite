import { HttpRequest, provideHttpClient, withInterceptors } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting, TestRequest } from '@angular/common/http/testing';
import { signal, type WritableSignal } from '@angular/core';
import { TestBed } from '@angular/core/testing';
import { vi, type Mock } from 'vitest';
import { Subject } from 'rxjs';
import { AUTH_ENV_CONFIG, tenantInterceptor } from 'core-auth';
import { environment } from '@env/environment';
import { CattleDataService } from './cattle-data.service';
import { CattleApiService } from './cattle-api.service';
import { OfflineStoreService } from './offline-store.service';
import { AuthService, TenantService } from 'core-auth';

/**
 * Session and tenant reset of the herd (#1111). Uses the REAL CattleApiService and the REAL tenant
 * interceptor, so the request count and the X-Tenant-ID header are what the server would see.
 */

const CATTLE_URL = `${environment.apiUrl_crud}/vw_cattle_kpi`;
const SAVED = '2026-11-16T10:00:00.000Z';
const row = (id: string, tenant: number) => ({ id, tenant_id: tenant });
const ids = (service: CattleDataService) => service.cattleList().map(a => a.id);

/** Lets promise continuations run after a flush. */
const settle = (): Promise<void> => new Promise(resolve => setTimeout(resolve, 0));

describe('CattleDataService reset on logout and tenant change (#1111)', () => {
  let activeId: WritableSignal<number | null>;
  let loggedIn: boolean;
  let changes: Subject<number | null>;
  let sessionEvents: Subject<{ type: string }>;
  let store: { get: Mock; put: Mock };
  let httpMock: HttpTestingController;
  let svc: CattleDataService;

  beforeEach(() => {
    activeId = signal<number | null>(3); // a stored tenant at boot
    loggedIn = true;
    changes = new Subject();
    sessionEvents = new Subject();
    store = { get: vi.fn().mockResolvedValue(null), put: vi.fn().mockResolvedValue(true) };
    vi.spyOn(console, 'error').mockImplementation(() => undefined);
    vi.spyOn(console, 'warn').mockImplementation(() => undefined);

    TestBed.configureTestingModule({
      providers: [
        provideHttpClient(withInterceptors([tenantInterceptor])),
        provideHttpClientTesting(),
        {
          provide: TenantService,
          useValue: {
            activeTenantId: activeId,
            activeTenant: signal(null),
            availableTenants: signal([]),
            activeTenantChanges$: changes
          }
        },
        {
          provide: AuthService,
          // Mirrors the real AuthService: no token or no active tenant means no scope (fail-closed).
          useValue: {
            getSessionScope: () => (loggedIn && activeId() ? { user: 'ana', id_company: activeId() } : null),
            getSessionState: () => (loggedIn ? 'valid' : 'expired'),
            sessionEvents$: sessionEvents
          }
        },
        {
          provide: AUTH_ENV_CONFIG,
          useValue: {
            apiUrl_crud: environment.apiUrl_crud,
            apiUrl_token: environment.apiUrl_token,
            apiUrl_ai: environment.apiUrl_ai,
            apiUrl_upload: environment.apiUrl_upload
          }
        },
        // Snapshots are keyed by the current scope, as in the real store.
        { provide: OfflineStoreService, useValue: store }
      ]
    });
    httpMock = TestBed.inject(HttpTestingController);
    svc = TestBed.inject(CattleDataService);
  });

  afterEach(() => {
    httpMock.verify();
    vi.restoreAllMocks();
  });

  /** Mirrors TenantService.setActiveTenant(): the signal changes first, then the emission. */
  function setTenant(id: number): void {
    activeId.set(id);
    changes.next(id);
  }

  /** Mirrors AuthService.logout(): clearContext() emits null, then the logout event. */
  function logout(): void {
    loggedIn = false;
    activeId.set(null);
    changes.next(null);
    sessionEvents.next({ type: 'logout' });
  }

  function login(id: number): void {
    loggedIn = true;
    setTenant(id);
  }

  /** Runs the tenant effect several times, as change detection would. */
  function ticks(times = 3): void {
    for (let i = 0; i < times; i++) TestBed.tick();
  }

  /** Livestock requests issued and not yet answered. Matching removes them from the pending list. */
  function pending(tenant?: number): TestRequest[] {
    return httpMock.match((req: HttpRequest<unknown>) =>
      req.url === CATTLE_URL && (tenant === undefined || req.headers.get('X-Tenant-ID') === String(tenant)));
  }

  /** Boot with tenant 3 and answer its one request. */
  async function loadTenantThree(rows: unknown[] = [row('a1', 3)]): Promise<void> {
    ticks();
    const [request] = pending(3);
    request.flush(rows);
    await settle();
  }

  it('boot with a stored tenant issues one request, and repeated ticks add none', async () => {
    ticks();
    const requests = pending();
    expect(requests.length).toBe(1);
    expect(requests[0].request.headers.get('X-Tenant-ID')).toBe('3');
    requests[0].flush([row('a1', 3)]);
    await settle();

    ticks();
    expect(pending().length).toBe(0);
    expect(ids(svc)).toEqual(['a1']);
  });

  it('one request per tenant switch, however many ticks follow', async () => {
    await loadTenantThree();

    setTenant(10);
    ticks(3);
    const requests = pending();
    expect(requests.length).toBe(1);
    expect(requests[0].request.headers.get('X-Tenant-ID')).toBe('10');

    ticks(3);
    expect(pending().length).toBe(0);

    requests[0].flush([row('b1', 10)]);
    await settle();
    expect(ids(svc)).toEqual(['b1']);
  });

  it('a switch empties the herd, its flags and hasLoadedOnce synchronously, before any tick', async () => {
    await loadTenantThree();
    expect(svc.hasLoadedOnce()).toBe(true);

    setTenant(10);
    expect(svc.cattleList()).toEqual([]);
    expect(svc.hasLoadedOnce()).toBe(false);
    expect(svc.loadError()).toBeNull();
    expect(svc.servedFromCache()).toBe(false);
    expect(svc.cacheSavedAt()).toBeNull();

    ticks();
    pending(10)[0].flush([row('b1', 10)]);
    await settle();
    expect(ids(svc)).toEqual(['b1']);
  });

  it('a same-id emission (login again, company rename) resets and reloads exactly once', async () => {
    await loadTenantThree();

    setTenant(3);
    expect(svc.cattleList()).toEqual([]);

    ticks();
    const requests = pending(3);
    expect(requests.length).toBe(1);
    requests[0].flush([row('a2', 3)]);
    await settle();
    expect(ids(svc)).toEqual(['a2']);
  });

  it('logout empties everything synchronously and issues no request', async () => {
    await loadTenantThree();

    logout();
    expect(svc.cattleList()).toEqual([]);
    expect(svc.hasLoadedOnce()).toBe(false);
    expect(svc.loadError()).toBeNull();

    ticks();
    expect(pending().length).toBe(0);
  });

  it('a response for the previous tenant that arrives after a switch is discarded', async () => {
    ticks();
    const stale = pending(3)[0];
    setTenant(10);
    ticks();
    const current = pending(10)[0];

    stale.flush([row('a1', 3)]);
    await settle();
    expect(svc.cattleList()).toEqual([]);

    current.flush([row('b1', 10)]);
    await settle();
    expect(ids(svc)).toEqual(['b1']);
  });

  it('A to B to A quickly: only the last switch is requested, and stale responses never show', async () => {
    ticks();
    const a1 = pending(3)[0];

    setTenant(10);
    setTenant(3);
    ticks();
    const requests = pending();
    expect(requests.length).toBe(1); // B was never requested: the effect ran once for the final tenant
    expect(requests[0].request.headers.get('X-Tenant-ID')).toBe('3');

    a1.flush([row('old', 3)]);
    await settle();
    expect(svc.cattleList()).toEqual([]);

    requests[0].flush([row('fresh', 3)]);
    await settle();
    expect(ids(svc)).toEqual(['fresh']);
  });

  it('A to B, then back to A after B was requested: the stale B and A responses are discarded', async () => {
    ticks();
    const a1 = pending(3)[0];
    setTenant(10);
    ticks();
    const b1 = pending(10)[0];
    setTenant(3);
    ticks();
    const a2 = pending(3)[0];

    b1.flush([row('b', 10)]);
    a1.flush([row('old', 3)]);
    await settle();
    expect(svc.cattleList()).toEqual([]);

    a2.flush([row('fresh', 3)]);
    await settle();
    expect(ids(svc)).toEqual(['fresh']);
  });

  it('a request started before logout is discarded even if the same user logs back into the same tenant', async () => {
    ticks();
    const old = pending(3)[0];

    logout();
    login(3);
    ticks();
    const fresh = pending(3);
    expect(fresh.length).toBe(1);

    old.flush([row('old', 3)]);
    await settle();
    expect(svc.cattleList()).toEqual([]);

    fresh[0].flush([row('fresh', 3)]);
    await settle();
    expect(ids(svc)).toEqual(['fresh']);
  });

  it('a server error after a switch leaves nothing from the previous tenant', async () => {
    await loadTenantThree();

    setTenant(10);
    ticks();
    pending(10)[0].flush({ error: true, message: 'boom' }, { status: 500, statusText: 'Server Error' });
    await settle();

    expect(svc.cattleList()).toEqual([]);
    expect(svc.loadError()).not.toBeNull();
    expect(svc.hasLoadedOnce()).toBe(false);
  });

  it('a network failure after a switch serves only the new tenant snapshot, never the previous one', async () => {
    // Real store semantics: the snapshot read is keyed by the current scope.
    store.get.mockImplementation(async () =>
      activeId() === 10
        ? { data: [row('snapB', 10)], savedAt: SAVED }
        : { data: [row('snapA', 3)], savedAt: SAVED });
    await loadTenantThree();

    setTenant(10);
    ticks();
    pending(10)[0].error(new ProgressEvent('error'));
    await settle();

    expect(ids(svc)).toEqual(['snapB']);
    expect(svc.servedFromCache()).toBe(true);
    expect(svc.cacheSavedAt()).toBe(SAVED);
    expect(svc.loadError()).toBeNull();
  });

  it('a network failure after a switch with no snapshot for the new tenant shows an error and no herd', async () => {
    await loadTenantThree();

    setTenant(10);
    ticks();
    pending(10)[0].error(new ProgressEvent('error'));
    await settle();

    expect(svc.cattleList()).toEqual([]);
    expect(svc.servedFromCache()).toBe(false);
    expect(svc.loadError()).not.toBeNull();
  });

});
