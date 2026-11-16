import { Component } from '@angular/core';
import { ComponentFixture, TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { environment } from '@env/environment';
import { ComplianceAlertCardComponent } from './compliance-alert-card.component';

const UPP_URL = `${environment.apiUrl_crud}/upp_compliance_status`;
const PSG_URL = `${environment.apiUrl_crud}/psg_compliance_status`;

const ok = (data: unknown[]) => ({ error: false, operation: 'getall', message: '', data });
const uppRow = (update_status: string) => ({ production_unit_id: 'upp-1', update_status, days_since_update: 400 });
const psgRow = (validity_status: string) => ({ psg_license_id: 'psg-1', validity_status });

/**
 * Renders the card inside a host element, so the real template, the real imports and the real
 * ComplianceService (driven through HttpTestingController) are all exercised.
 */
@Component({
  standalone: true,
  imports: [ComplianceAlertCardComponent],
  template: `<app-compliance-alert-card />`
})
class HostComponent {}

describe('ComplianceAlertCardComponent', () => {
  let fixture: ComponentFixture<HostComponent>;
  let httpMock: HttpTestingController;

  beforeEach(() => {
    TestBed.configureTestingModule({
      imports: [HostComponent],
      providers: [provideRouter([]), provideHttpClient(), provideHttpClientTesting()]
    });
    httpMock = TestBed.inject(HttpTestingController);
    fixture = TestBed.createComponent(HostComponent);
    fixture.detectChanges(); // runs ngOnInit: both loads start
  });

  afterEach(() => {
    // Some loading-state tests intentionally leave requests pending; drain them before verify().
    httpMock.match(() => true);
    httpMock.verify();
  });

  const el = (): HTMLElement => fixture.nativeElement;
  const text = (): string => el().textContent ?? '';
  const greenCount = (): number => el().querySelectorAll('.bg-green-lt').length;
  const flushUpp = (body: any, status?: number) =>
    httpMock.expectOne(UPP_URL).flush(body, status ? { status, statusText: 'Error' } : undefined);
  const flushPsg = (body: any, status?: number) =>
    httpMock.expectOne(PSG_URL).flush(body, status ? { status, statusText: 'Error' } : undefined);
  const render = () => fixture.detectChanges();

  describe('loading', () => {
    it('shows the loading state with role status while both sources are pending', () => {
      render();
      expect(el().querySelector('[data-testid="compliance-loading"]')).not.toBeNull();
      expect(el().querySelector('[role="status"]')).not.toBeNull();
      expect(greenCount()).toBe(0);
    });

    it('never shows green while one source is still pending after the other failed', () => {
      flushUpp(null, 500);
      render();
      expect(el().querySelector('[data-testid="compliance-loading"]')).not.toBeNull();
      expect(greenCount()).toBe(0);
      expect(el().querySelector('[data-testid="compliance-partial"]')).toBeNull();
      flushPsg(ok([]));
    });
  });

  describe('all-clear', () => {
    it('shows green only when both sources loaded with nothing to attend', () => {
      flushUpp(ok([]));
      flushPsg(ok([]));
      render();
      expect(el().querySelector('[data-testid="compliance-allclear"]')).not.toBeNull();
      expect(greenCount()).toBe(1);
      expect(text()).toContain('Cumplimiento normativo al día');
    });
  });

  describe('attention', () => {
    it('shows the red attention state when a UPP is expired', () => {
      flushUpp(ok([uppRow('EXPIRED')]));
      flushPsg(ok([]));
      render();
      expect(el().querySelector('[data-testid="compliance-attention"]')).not.toBeNull();
      expect(text()).toContain('1 UPP requieren atención normativa');
      expect(greenCount()).toBe(0);
    });

    it('counts expired PSG licences in the attention title', () => {
      flushUpp(ok([]));
      flushPsg(ok([psgRow('EXPIRED')]));
      render();
      expect(text()).toContain('1 PSG vencidas');
      expect(greenCount()).toBe(0);
    });
  });

  describe('unknown (both sources failed)', () => {
    it('shows the unknown state with a retry action and never green', () => {
      flushUpp(null, 500);
      flushPsg(null, 500);
      render();
      expect(el().querySelector('[data-testid="compliance-unknown"]')).not.toBeNull();
      expect(el().querySelector('[role="alert"]')).not.toBeNull();
      expect(text()).toContain('No se pudo verificar el cumplimiento normativo');
      expect(text()).toContain('El servicio no respondió');
      expect(el().querySelector('[data-testid="compliance-retry"]')).not.toBeNull();
      expect(greenCount()).toBe(0);
    });

    it('uses the network-specific message when the failure is a network failure', () => {
      httpMock.expectOne(UPP_URL).error(new ProgressEvent('error'));
      httpMock.expectOne(PSG_URL).error(new ProgressEvent('error'));
      render();
      expect(text()).toContain('Sin conexión');
      expect(greenCount()).toBe(0);
    });

    it('retry reloads both sources when both failed', () => {
      flushUpp(null, 500);
      flushPsg(null, 500);
      render();

      el().querySelector<HTMLButtonElement>('[data-testid="compliance-retry"]')!.click();
      httpMock.expectOne(UPP_URL).flush(ok([]));
      httpMock.expectOne(PSG_URL).flush(ok([]));
      render();

      expect(el().querySelector('[data-testid="compliance-allclear"]')).not.toBeNull();
    });
  });

  describe('partial (one source failed)', () => {
    it('shows the partial state with no all-clear when UPP failed and PSG is empty', () => {
      flushUpp(null, 500);
      flushPsg(ok([]));
      render();
      expect(el().querySelector('[data-testid="compliance-partial"]')).not.toBeNull();
      expect(text()).toContain('Verificación incompleta');
      expect(text()).toContain('No se pudo verificar las UPP');
      expect(greenCount()).toBe(0);
    });

    it('shows the working source counts with the warning when PSG failed and a PSG is expired', () => {
      flushUpp(ok([]));
      flushPsg(null, 500);
      render();
      expect(el().querySelector('[data-testid="compliance-partial"]')).not.toBeNull();
      expect(text()).toContain('No se pudo verificar las licencias PSG');
      expect(greenCount()).toBe(0);
    });

    it('does not report a UPP count for a failed UPP source', () => {
      flushUpp(null, 500);
      flushPsg(ok([psgRow('EXPIRED')]));
      render();
      expect(text()).toContain('1 PSG vencidas');
      expect(text()).not.toContain('0 UPP');
      expect(greenCount()).toBe(0);
    });

    it('retry reloads only the failed source', () => {
      flushUpp(null, 500);
      flushPsg(ok([]));
      render();

      el().querySelector<HTMLButtonElement>('[data-testid="compliance-retry"]')!.click();
      httpMock.expectNone(PSG_URL);
      httpMock.expectOne(UPP_URL).flush(ok([]));
      render();

      expect(el().querySelector('[data-testid="compliance-allclear"]')).not.toBeNull();
    });
  });
});
