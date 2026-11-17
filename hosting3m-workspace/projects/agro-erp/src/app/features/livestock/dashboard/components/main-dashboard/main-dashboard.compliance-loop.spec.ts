import { HttpRequest, provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { signal, type WritableSignal } from '@angular/core';
import { ComponentFixture, TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { vi } from 'vitest';
import { AuthService, TenantService } from 'core-auth';
import { Subject } from 'rxjs';
import { environment } from '@env/environment';
import { CattleApiService } from '@core/services/cattle-api.service';
import { CattleDataService } from '@core/services/cattle-data.service';
import { SaleService } from '@core/services/sale.service';
import { ThemeService } from '@core/services/theme.service';
import { wireComplianceSessionReset } from '@core/utils/compliance-session-reset.util';
import { MainDashboardComponent } from './main-dashboard.component';

const UPP_URL = `${environment.apiUrl_crud}/upp_compliance_status`;
const PSG_URL = `${environment.apiUrl_crud}/psg_compliance_status`;
const ok = (data: unknown[]) => ({ error: false, operation: 'getall', message: '', data });

/** Lets queued microtasks and promise continuations run. */
const settle = (): Promise<void> => new Promise(resolve => setTimeout(resolve, 0));

/**
 * Regression for the compliance request loop after login (#1109, commit 8aaf108).
 *
 * Mounts the REAL dashboard (real tenant effect), the REAL ComplianceService and the REAL
 * tenant-change wiring, with only the cattle/sales/theme collaborators stubbed. Responses are
 * flushed round after round with effects flushed in between. A healthy app issues exactly one
 * UPP and one PSG request for the tenant, however many effect runs follow.
 */
describe('MainDashboardComponent compliance requests do not loop (#1109)', () => {
  let fixture: ComponentFixture<MainDashboardComponent>;
  let httpMock: HttpTestingController;
  let activeTenantId: WritableSignal<number | null>;

  beforeEach(() => {
    activeTenantId = signal<number | null>(1);
    TestBed.configureTestingModule({
      providers: [
        provideRouter([]),
        provideHttpClient(),
        provideHttpClientTesting(),
        {
          provide: TenantService,
          useValue: {
            activeTenantId,
            activeTenant: signal({ id_company: 1, role: 'ADMIN' }),
            activeTenantChanges$: new Subject<number | null>()
          }
        },
        { provide: AuthService, useValue: { sessionEvents$: new Subject<{ type: string }>() } },
        { provide: CattleApiService, useValue: { getExpenses: vi.fn().mockResolvedValue([]) } },
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
        { provide: SaleService, useValue: { getSaleIncome: vi.fn().mockResolvedValue([]) } },
        { provide: ThemeService, useValue: { currentTheme: signal('dark') } }
      ]
    });
    httpMock = TestBed.inject(HttpTestingController);
    TestBed.runInInjectionContext(() => wireComplianceSessionReset());
    fixture = TestBed.createComponent(MainDashboardComponent);
  });

  afterEach(() => {
    fixture.destroy();
    httpMock.match(() => true);
  });

  it('issues exactly one UPP and one PSG request for the active tenant across repeated effect runs', async () => {
    const requests: Record<string, number> = { [UPP_URL]: 0, [PSG_URL]: 0 };

    for (let round = 0; round < 6; round++) {
      TestBed.flushEffects();
      await settle();
      const open = httpMock.match((req: HttpRequest<unknown>) => req.url === UPP_URL || req.url === PSG_URL);
      for (const req of open) {
        requests[req.request.url] += 1;
        req.flush(ok([]));
      }
    }
    TestBed.flushEffects();
    await settle();

    expect(requests[UPP_URL]).toBe(1);
    expect(requests[PSG_URL]).toBe(1);
    expect(httpMock.match((req: HttpRequest<unknown>) => req.url === UPP_URL || req.url === PSG_URL)).toEqual([]);
  });
});
