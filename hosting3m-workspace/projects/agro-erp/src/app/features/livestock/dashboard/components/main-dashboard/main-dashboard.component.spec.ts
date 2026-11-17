import { signal, type WritableSignal } from '@angular/core';
import { ComponentFixture, TestBed } from '@angular/core/testing';
import { vi, type Mock } from 'vitest';
import { provideRouter } from '@angular/router';
import { TenantService } from 'core-auth';
import { CattleApiService } from '@core/services/cattle-api.service';
import { CattleDataService } from '@core/services/cattle-data.service';
import { SaleService } from '@core/services/sale.service';
import { ThemeService } from '@core/services/theme.service';
import { ComplianceService } from '@features/compliance/services/compliance.service';
import { MainDashboardComponent } from './main-dashboard.component';

/** Lets pending promise continuations (the rejected Promise.all) run to completion. */
const settle = (): Promise<void> => new Promise(resolve => setTimeout(resolve, 0));

/**
 * Logic-only spec for the dashboard load pipeline (#1109). The template and child components are
 * replaced with an empty template; every collaborator is a stub, so no HTTP is involved.
 */
describe('MainDashboardComponent tenant load (#1109)', () => {
  let fixture: ComponentFixture<MainDashboardComponent>;
  let component: MainDashboardComponent;
  let activeTenantId: WritableSignal<number | null>;
  let getExpenses: Mock;
  let loadUppStatus: Mock;
  let loadPsgStatus: Mock;

  beforeEach(() => {
    activeTenantId = signal<number | null>(1);
    // Pending by default: each test decides how the expenses call settles.
    getExpenses = vi.fn().mockReturnValue(new Promise(() => undefined));
    loadUppStatus = vi.fn();
    loadPsgStatus = vi.fn();

    TestBed.overrideComponent(MainDashboardComponent, { set: { imports: [], template: '' } });
    TestBed.configureTestingModule({
      providers: [
        provideRouter([]),
        {
          provide: TenantService,
          useValue: {
            activeTenantId,
            activeTenant: signal({ id_company: 1, role: 'ADMIN' })
          }
        },
        { provide: CattleApiService, useValue: { getExpenses } },
        {
          provide: CattleDataService,
          useValue: {
            cattleList: signal([]),
            loadError: signal(null),
            hasLoadedOnce: signal(true),
            servedFromCache: signal(false),
            cacheSavedAt: signal(null),
            loadCattleData: vi.fn().mockResolvedValue(undefined)
          }
        },
        { provide: ComplianceService, useValue: { loadUppStatus, loadPsgStatus } },
        { provide: SaleService, useValue: { getSaleIncome: vi.fn().mockResolvedValue([]) } },
        { provide: ThemeService, useValue: { currentTheme: signal('dark') } }
      ]
    });

    fixture = TestBed.createComponent(MainDashboardComponent);
    component = fixture.componentInstance;
  });

  afterEach(() => fixture.destroy());

  it('still forces the compliance reload when the cattle/expenses call fails', async () => {
    getExpenses.mockReturnValue(Promise.reject(new Error('gateway caído')));

    TestBed.flushEffects(); // runs the tenant effect: the initial load starts
    await settle();

    expect(loadUppStatus).toHaveBeenCalledWith(true);
    expect(loadPsgStatus).toHaveBeenCalledWith(true);
  });

  it('forces the compliance reload before waiting on the cattle/expenses call', () => {
    TestBed.flushEffects();

    expect(loadUppStatus).toHaveBeenCalledWith(true);
    expect(loadPsgStatus).toHaveBeenCalledWith(true);
    expect(getExpenses).toHaveBeenCalled();
  });

  it('clears the previous tenant expenses when a tenant change starts its initial load', () => {
    getExpenses.mockReturnValue(Promise.resolve([{ id: 'gasto-A', amount: 900 }]));
    TestBed.flushEffects();
    return settle().then(() => {
      expect(component.expensesList().length).toBe(1);

      // Tenant B's expenses call never settles: the list must already be empty, not A's rows.
      getExpenses.mockReturnValue(new Promise(() => undefined));
      activeTenantId.set(2);
      TestBed.flushEffects();

      expect(component.expensesList()).toEqual([]);
    });
  });

  it('keeps the last expenses on a refresh (no reset outside the initial load)', async () => {
    getExpenses.mockReturnValue(Promise.resolve([{ id: 'gasto-A' }]));
    TestBed.flushEffects();
    await settle();
    expect(component.expensesList().length).toBe(1);

    getExpenses.mockReturnValue(new Promise(() => undefined));
    void component.refreshNow(); // not awaited: the pending expenses call never settles

    expect(component.expensesList().length).toBe(1);
  });
});
