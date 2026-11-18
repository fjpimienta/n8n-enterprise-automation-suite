import { HttpTestingController, provideHttpClientTesting, TestRequest } from '@angular/common/http/testing';
import { provideHttpClient } from '@angular/common/http';
import { TestBed } from '@angular/core/testing';
import { signal, computed } from '@angular/core';
import { environment } from '@env/environment';
import { AuthService, TenantService } from 'core-auth';
import { Subject } from 'rxjs';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import {
  EMPTY_ENVELOPE,
  ERROR_ENVELOPE,
  SYNTHETIC_OTHER_TENANT,
  SYNTHETIC_TENANT,
  envelope,
  eventWire,
  herdWire,
} from '../testing/palpation.fixtures';
import { PalpationReportService, PALPATION_MAX_PAGES, PALPATION_PAGE_SIZE } from './palpation-report.service';

/** Synthetic tenant store: the same surface the service reads from TenantService. */
class TenantStub {
  readonly active = signal<{ id_company: number; role: string } | null>({ id_company: SYNTHETIC_TENANT, role: 'ADMIN' });
  readonly activeTenant = this.active.asReadonly();
  readonly activeTenantId = computed(() => this.active()?.id_company ?? null);
  readonly changes = new Subject<number | null>();
  readonly activeTenantChanges$ = this.changes.asObservable();
}

/** Synthetic auth store: the same surface the service reads from AuthService. */
class AuthStub {
  state: 'valid' | 'grace' | 'expired' = 'valid';
  readonly events = new Subject<{ type: 'logout' } | { type: 'login' }>();
  readonly sessionEvents$ = this.events.asObservable();
  getSessionState(): 'valid' | 'grace' | 'expired' {
    return this.state;
  }
}

const EV = `${environment.apiUrl_crud}/vw_palpation_events`;
const HD = `${environment.apiUrl_crud}/vw_palpation_herd`;
const tick = () => new Promise<void>((resolve) => setTimeout(resolve, 0));

describe('PalpationReportService', () => {
  let tenant: TenantStub;
  let auth: AuthStub;
  let svc: PalpationReportService;
  let http: HttpTestingController;

  beforeEach(() => {
    tenant = new TenantStub();
    auth = new AuthStub();
    TestBed.configureTestingModule({
      providers: [
        provideHttpClient(),
        provideHttpClientTesting(),
        { provide: TenantService, useValue: tenant },
        { provide: AuthService, useValue: auth },
      ],
    });
    svc = TestBed.inject(PalpationReportService);
    http = TestBed.inject(HttpTestingController);
  });

  afterEach(() => {
    http.match(() => true); // discard any request a test chose not to answer
  });

  /** Answers the one outstanding request of a URL with a text body and lets the service continue. */
  async function answer(url: string, body: string): Promise<TestRequest> {
    const req = http.expectOne((r) => r.url === url);
    req.flush(body);
    await tick();
    return req;
  }

  /** Answers the outstanding request of a URL with an HTTP error. */
  async function fail(url: string, status: number): Promise<void> {
    const req = http.expectOne((r) => r.url === url);
    req.flush('', { status, statusText: 'synthetic' });
    await tick();
  }

  describe('before any request', () => {
    it('sends nothing without an active company (sin-tenant)', async () => {
      tenant.active.set(null);
      await svc.load();
      http.expectNone(() => true);
      expect(svc.status()).toBe('sin-tenant');
    });

    it('sends nothing for OWNER or CUSTOMER (sin-permiso)', async () => {
      for (const role of ['OWNER', 'CUSTOMER', 'GUEST', '']) {
        tenant.active.set({ id_company: SYNTHETIC_TENANT, role });
        await svc.load();
        expect(svc.status()).toBe('sin-permiso');
      }
      http.expectNone(() => true);
    });

    it('allows ADMIN and EDITOR, and normalises the role before comparing', () => {
      tenant.active.set({ id_company: SYNTHETIC_TENANT, role: 'editor' });
      expect(svc.canRead()).toBe(true);
      tenant.active.set({ id_company: SYNTHETIC_TENANT, role: ' ADMIN ' });
      expect(svc.canRead()).toBe(true);
    });

    it('sends nothing with an expired session, and nothing in grace (the auth interceptor would log out)', async () => {
      auth.state = 'expired';
      await svc.load();
      expect(svc.status()).toBe('error');
      expect(svc.reason()).toBe('session-expired');
      auth.state = 'grace';
      await svc.load();
      expect(svc.reason()).toBe('network');
      http.expectNone(() => true);
    });
  });

  describe('loading', () => {
    it('loads both views, sends the unique sort key and the explicit page size, and shows the rows', async () => {
      const loading = svc.load();
      const evReq = http.expectOne((r) => r.url === EV);
      expect(evReq.request.body).toEqual({ operation: 'getall', sort_by: 'health_log_id', limit: PALPATION_PAGE_SIZE, offset: 0 });
      evReq.flush(envelope([eventWire(), eventWire({ health_log_id: 'ev-0002' })]));
      await answer(HD, envelope([herdWire()]));
      await loading;
      expect(svc.status()).toBe('listo');
      expect(svc.events().length).toBe(2);
      expect(svc.herd().length).toBe(1);
      expect(svc.events()[0]?.event_date).toBe('2026-11-10');
    });

    it('shows "vacio" for the empty collection (data:[{}]), which is not an error', async () => {
      const loading = svc.load();
      http.expectOne((r) => r.url === EV).flush(EMPTY_ENVELOPE);
      await answer(HD, EMPTY_ENVELOPE);
      await loading;
      expect(svc.status()).toBe('vacio');
      expect(svc.events()).toEqual([]);
      expect(svc.reason()).toBeNull();
    });

    it('treats an empty body as an error and shows no rows (never "zero animals")', async () => {
      const loading = svc.load();
      http.expectOne((r) => r.url === EV).flush('');
      await answer(HD, envelope([herdWire()]));
      await loading;
      expect(svc.status()).toBe('error');
      expect(svc.reason()).toBe('empty-body');
      expect(svc.events()).toEqual([]);
      expect(svc.herd()).toEqual([]);
    });

    it('treats error:true on HTTP 200 as an error', async () => {
      const loading = svc.load();
      http.expectOne((r) => r.url === EV).flush(envelope([eventWire()]));
      await answer(HD, ERROR_ENVELOPE);
      await loading;
      expect(svc.status()).toBe('error');
      expect(svc.reason()).toBe('gateway-error');
    });

    it('discards the whole response when one row belongs to another company', async () => {
      const loading = svc.load();
      http.expectOne((r) => r.url === EV).flush(envelope([eventWire(), eventWire({ id_company: SYNTHETIC_OTHER_TENANT, health_log_id: 'x' })]));
      await answer(HD, envelope([herdWire()]));
      await loading;
      expect(svc.status()).toBe('error');
      expect(svc.reason()).toBe('foreign-company');
      expect(svc.events()).toEqual([]);
    });

    it('maps HTTP 500 to http-error and a status-0 failure (offline) to network', async () => {
      const first = svc.load();
      await fail(EV, 500);
      await answer(HD, EMPTY_ENVELOPE);
      await first;
      expect(svc.reason()).toBe('http-error');

      const second = svc.load();
      await fail(EV, 0);
      await answer(HD, EMPTY_ENVELOPE);
      await second;
      expect(svc.reason()).toBe('network');
    });
  });

  describe('paging', () => {
    it('follows the pages until one is shorter than the page size, and keeps every row once', async () => {
      const loading = svc.load();
      const first = Array.from({ length: PALPATION_PAGE_SIZE }, (_, i) => eventWire({ health_log_id: `ev-${i}` }));
      const second = [eventWire({ health_log_id: 'ev-last-1' }), eventWire({ health_log_id: 'ev-last-2' })];
      http.expectOne((r) => r.url === EV && r.body.offset === 0).flush(envelope(first));
      await tick();
      const next = http.expectOne((r) => r.url === EV && r.body.offset === PALPATION_PAGE_SIZE);
      expect(next.request.body).toMatchObject({ sort_by: 'health_log_id', limit: PALPATION_PAGE_SIZE });
      next.flush(envelope(second));
      await answer(HD, EMPTY_ENVELOPE);
      await loading;
      expect(svc.status()).toBe('listo');
      expect(svc.events().length).toBe(PALPATION_PAGE_SIZE + 2);
      expect(new Set(svc.events().map((e) => e.health_log_id)).size).toBe(PALPATION_PAGE_SIZE + 2);
    });

    it('treats a key repeated across pages as an unstable paging error', async () => {
      const loading = svc.load();
      const first = Array.from({ length: PALPATION_PAGE_SIZE }, (_, i) => eventWire({ health_log_id: `ev-${i}` }));
      http.expectOne((r) => r.url === EV && r.body.offset === 0).flush(envelope(first));
      await tick();
      http.expectOne((r) => r.url === EV && r.body.offset === PALPATION_PAGE_SIZE).flush(envelope([eventWire({ health_log_id: 'ev-0' })]));
      await answer(HD, EMPTY_ENVELOPE);
      await loading;
      expect(svc.status()).toBe('error');
      expect(svc.reason()).toBe('unexpected-shape');
      expect(svc.events()).toEqual([]);
    });

    it('marks the report truncated after the maximum number of full pages, and keeps the rows as partial', async () => {
      const loading = svc.load();
      for (let page = 0; page < PALPATION_MAX_PAGES; page += 1) {
        const rows = Array.from({ length: PALPATION_PAGE_SIZE }, (_, i) => eventWire({ health_log_id: `p${page}-${i}` }));
        http.expectOne((r) => r.url === EV && r.body.offset === page * PALPATION_PAGE_SIZE).flush(envelope(rows));
        await tick();
      }
      await answer(HD, EMPTY_ENVELOPE);
      await loading;
      expect(svc.status()).toBe('truncado');
      expect(svc.events().length).toBe(PALPATION_MAX_PAGES * PALPATION_PAGE_SIZE);
    });
  });

  describe('superseded answers', () => {
    it('drops an answer that arrives after the tenant changed (no rows from the old company)', async () => {
      const loading = svc.load();
      tenant.changes.next(null); // the company changes while requests are in flight
      http.expectOne((r) => r.url === EV).flush(envelope([eventWire()]));
      await answer(HD, envelope([herdWire()]));
      await loading;
      expect(svc.status()).toBe('sin-tenant');
      expect(svc.events()).toEqual([]);
      expect(svc.herd()).toEqual([]);
    });

    it('clears everything on logout', async () => {
      const loading = svc.load();
      http.expectOne((r) => r.url === EV).flush(envelope([eventWire()]));
      await answer(HD, envelope([herdWire()]));
      await loading;
      expect(svc.events().length).toBe(1);
      auth.events.next({ type: 'logout' });
      expect(svc.status()).toBe('sin-tenant');
      expect(svc.events()).toEqual([]);
      expect(svc.herd()).toEqual([]);
    });
  });

  describe('drawer timeline', () => {
    it('filters one animal by livestock_id, sorts by the unique key and returns its events', async () => {
      const pending = svc.loadHistory('an-0001');
      const req = http.expectOne((r) => r.url === EV);
      expect(req.request.body).toEqual({
        operation: 'getall',
        filter: { livestock_id: 'an-0001' },
        sort_by: 'health_log_id',
        limit: PALPATION_PAGE_SIZE,
        offset: 0,
      });
      req.flush(envelope([eventWire(), eventWire({ health_log_id: 'ev-0002', result: 'PREÑADA', gestation_days: 90 })]));
      const r = await pending;
      expect(r.ok).toBe(true);
      expect(r.ok && r.rows.length).toBe(2);
    });

    it('answers no-tenant and no-permission without sending a request', async () => {
      tenant.active.set(null);
      expect(await svc.loadHistory('an-0001')).toEqual({ ok: false, reason: 'no-tenant' });
      tenant.active.set({ id_company: SYNTHETIC_TENANT, role: 'OWNER' });
      expect(await svc.loadHistory('an-0001')).toEqual({ ok: false, reason: 'no-permission' });
      http.expectNone(() => true);
    });
  });
});
