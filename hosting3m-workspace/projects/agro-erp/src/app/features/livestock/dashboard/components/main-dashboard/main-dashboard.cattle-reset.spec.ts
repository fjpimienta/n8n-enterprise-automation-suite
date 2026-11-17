import { signal, type WritableSignal } from '@angular/core';
import { ComponentFixture, TestBed } from '@angular/core/testing';
import { vi } from 'vitest';
import { provideRouter } from '@angular/router';
import { Subject } from 'rxjs';
import { AuthService, TenantService } from 'core-auth';
import { CattleApiService } from '@core/services/cattle-api.service';
import { CattleDataService } from '@core/services/cattle-data.service';
import { OfflineStoreService } from '@core/services/offline-store.service';
import { SaleService } from '@core/services/sale.service';
import { ThemeService } from '@core/services/theme.service';
import { ComplianceService } from '@features/compliance/services/compliance.service';
import { MainDashboardComponent } from './main-dashboard.component';

/**
 * What the herd looks like on the dashboard across a tenant change and a logout (#1111). The REAL
 * CattleDataService is used; only its HTTP dependency is controlled. The full template needs about
 * fifteen child components, so it is replaced with a probe that renders the same herd signal.
 */

const PROBE = `
  <span class="herd-count">{{ cattleList().length }}</span>
  @for (animal of cattleList(); track animal.id) {
    <span class="herd-id">{{ animal.id }}</span>
  }`;

type Deferred = { resolve: (rows: unknown[]) => void; reject: (error: unknown) => void };

const settle = (): Promise<void> => new Promise(resolve => setTimeout(resolve, 0));

describe('MainDashboardComponent herd across a tenant change and logout (#1111)', () => {
  let fixture: ComponentFixture<MainDashboardComponent>;
  let activeId: WritableSignal<number | null>;
  let activeTenant: WritableSignal<{ id_company: number; role: string } | null>;
  let changes: Subject<number | null>;
  let sessionEvents: Subject<{ type: string }>;
  let loggedIn: boolean;
  let calls: Deferred[];

  beforeEach(() => {
    activeId = signal<number | null>(3);
    activeTenant = signal<{ id_company: number; role: string } | null>({ id_company: 3, role: 'ADMIN' });
    changes = new Subject();
    sessionEvents = new Subject();
    loggedIn = true;
    calls = [];

    TestBed.overrideComponent(MainDashboardComponent, { set: { imports: [], template: PROBE } });
    TestBed.configureTestingModule({
      providers: [
        provideRouter([]),
        {
          provide: TenantService,
          useValue: {
            activeTenantId: activeId,
            activeTenant,
            availableTenants: signal([]),
            activeTenantChanges$: changes
          }
        },
        {
          provide: AuthService,
          useValue: {
            getSessionScope: () => (loggedIn && activeId() ? { user: 'ana', id_company: activeId() } : null),
            getSessionState: () => (loggedIn ? 'valid' : 'expired'),
            sessionEvents$: sessionEvents
          }
        },
        {
          provide: CattleApiService,
          useValue: {
            // Each herd request stays pending until the test answers it.
            getAllLivestock: vi.fn(() => new Promise((resolve, reject) => calls.push({ resolve, reject }))),
            getExpenses: vi.fn().mockResolvedValue([])
          }
        },
        { provide: OfflineStoreService, useValue: { get: vi.fn().mockResolvedValue(null), put: vi.fn().mockResolvedValue(true) } },
        { provide: ComplianceService, useValue: { loadUppStatus: vi.fn(), loadPsgStatus: vi.fn() } },
        { provide: SaleService, useValue: { getSaleIncome: vi.fn().mockResolvedValue([]) } },
        { provide: ThemeService, useValue: { currentTheme: signal('dark') } }
      ]
    });

    vi.spyOn(console, 'error').mockImplementation(() => undefined);
    vi.spyOn(console, 'warn').mockImplementation(() => undefined);
    fixture = TestBed.createComponent(MainDashboardComponent);
  });

  afterEach(() => {
    fixture.destroy();
    vi.restoreAllMocks();
  });

  /** What a user would see right now: the herd ids rendered by the probe. */
  function herdOnScreen(): string[] {
    fixture.detectChanges();
    return Array.from(fixture.nativeElement.querySelectorAll('.herd-id') as NodeListOf<HTMLElement>)
      .map(element => element.textContent?.trim() ?? '');
  }

  /** Mirrors TenantService.setActiveTenant(): the signal changes first, then the emission. */
  function setTenant(id: number): void {
    activeId.set(id);
    activeTenant.set({ id_company: id, role: 'ADMIN' });
    changes.next(id);
  }

  it('shows the previous tenant herd at no point of a switch, before the new load settles', async () => {
    TestBed.flushEffects();
    await settle();
    expect(calls.length).toBe(1);
    calls[0].resolve([{ id: 'a1', tenant_id: 3 }, { id: 'a2', tenant_id: 3 }]);
    await settle();
    expect(herdOnScreen()).toEqual(['a1', 'a2']);

    setTenant(10); // B's request is pending: nothing of A may render
    expect(herdOnScreen()).toEqual([]);

    TestBed.flushEffects();
    await settle();
    expect(calls.length).toBe(2);
    expect(herdOnScreen()).toEqual([]);

    calls[1].resolve([{ id: 'b1', tenant_id: 10 }]);
    await settle();
    expect(herdOnScreen()).toEqual(['b1']);
  });

  it('shows no previous-tenant herd when the new tenant load fails', async () => {
    TestBed.flushEffects();
    await settle();
    calls[0].resolve([{ id: 'a1', tenant_id: 3 }]);
    await settle();
    expect(herdOnScreen()).toEqual(['a1']);

    setTenant(10);
    TestBed.flushEffects();
    await settle();
    calls[1].reject(new Error('gateway caído'));
    await settle();

    expect(herdOnScreen()).toEqual([]);
  });

  it('shows no herd after logout, from the moment the session ends', async () => {
    TestBed.flushEffects();
    await settle();
    calls[0].resolve([{ id: 'a1', tenant_id: 3 }]);
    await settle();
    expect(herdOnScreen()).toEqual(['a1']);

    loggedIn = false;
    activeId.set(null);
    activeTenant.set(null);
    changes.next(null);
    sessionEvents.next({ type: 'logout' });

    expect(herdOnScreen()).toEqual([]);
    TestBed.flushEffects();
    await settle();
    expect(calls.length).toBe(1); // logout issues no request
  });
});
