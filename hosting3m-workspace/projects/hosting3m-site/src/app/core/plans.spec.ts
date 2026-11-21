import { TestBed } from '@angular/core/testing';
import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import {
  CatalogPlan,
  PlansService,
  formatMoney,
  groupByFamily,
  isQuote,
  parsePlans,
  priceSuffix,
  setupLine,
  shownAmount,
} from './plans';
import { RUNTIME } from './runtime-config';
import snapshot from '../data/plans-snapshot.json';

const api = (over: Record<string, unknown> = {}) => ({
  plan_key: 'vps-1', family: 'vps', name: 'VPS 1', summary: 's', features: ['a'], badge: null, billing_period: 'monthly',
  price_amount: 100, managed_amount: null, promo_amount: null, promo_months: null, renewal_amount: null, setup_fee: null,
  term_months: null, currency: 'MXN', tax_included: false, service_label: 'Renta de Servidores VPS',
  price_checked_at: '2026-11-01', valid_until: null, is_featured: false, sort_order: 1, ...over,
});
const one = (over: Record<string, unknown> = {}): CatalogPlan => parsePlans([api(over)])[0];

describe('parsePlans (type guard)', () => {
  it('ignores non-arrays, [{}] and entries without key, name or a known family', () => {
    expect(parsePlans(null)).toEqual([]);
    expect(parsePlans([{}])).toEqual([]);
    expect(parsePlans([api({ family: 'unknown' }), api({ name: '' }), 'x', null])).toEqual([]);
  });

  it('caps items, string lengths and rejects negative or non-finite numbers', () => {
    const many = Array.from({ length: 80 }, (_, i) => api({ plan_key: `k${i}` }));
    expect(parsePlans(many)).toHaveLength(50);
    const p = one({ name: 'x'.repeat(500), features: Array.from({ length: 99 }, () => 'f'.repeat(999)), price_amount: -1, setup_fee: Infinity, renewal_amount: 'abc' });
    expect(p.name).toHaveLength(80);
    expect(p.features).toHaveLength(20);
    expect(p.features[0]).toHaveLength(160);
    expect([p.price, p.setupFee, p.renewalPrice]).toEqual([null, null, null]);
  });

  it('accepts numeric strings (Postgres numerics) and unknown billing periods become quote', () => {
    expect(one({ price_amount: '1234.50' }).price).toBe(1234.5);
    expect(one({ billing_period: 'weekly' }).billing).toBe('quote');
  });
});

describe('price presentation', () => {
  it('formats whole pesos without decimals and keeps two decimals only for cents', () => {
    expect(formatMoney(2880)).toBe('$2,880');
    expect(formatMoney(24.29)).toBe('$24.29');
    expect(formatMoney(1234.5)).toBe('$1,234.50');
    expect(formatMoney(0)).toBe('$0');
  });

  it('says "MXN / año + IVA" for yearly without tax and "IVA incluido" when included', () => {
    expect(priceSuffix(one({ billing_period: 'yearly', tax_included: false }))).toBe('MXN / año + IVA');
    expect(priceSuffix(one({ billing_period: 'yearly', tax_included: true }))).toBe('MXN / año IVA incluido');
    expect(priceSuffix(one({ tax_included: null }))).toBe('MXN / mes');
  });

  it('switches the shown amount with the managed toggle only when a managed price exists', () => {
    const p = one({ price_amount: 100, managed_amount: 250 });
    expect(shownAmount(p, false)).toBe(100);
    expect(shownAmount(p, true)).toBe(250);
    expect(shownAmount(one({ managed_amount: null }), true)).toBe(100);
  });

  it('asks for a quote when billing is quote or the price is null', () => {
    expect(isQuote(one({ billing_period: 'quote', price_amount: 5 }), false)).toBe(true);
    expect(isQuote(one({ price_amount: null }), false)).toBe(true);
    expect(isQuote(one(), false)).toBe(false);
  });

  it('shows no setup line when null, except "cotiza" for VPS', () => {
    expect(setupLine(one({ family: 'hosting', setup_fee: null }))).toBeNull();
    expect(setupLine(one({ family: 'vps', setup_fee: null }))).toBe('Instalación inicial: cotiza');
    expect(setupLine(one({ setup_fee: 500 }))).toBe('Instalación inicial: $500');
  });

  it('groups by family in catalog order', () => {
    const groups = groupByFamily(parsePlans([api({ plan_key: 'd', family: 'domain' }), api()]));
    expect(groups.map((g) => g.family)).toEqual(['vps', 'domain']);
  });
});

describe('PlansService', () => {
  // Unit tests run with the development runtime config (mock API); these tests exercise the real HTTP path.
  let mock: boolean;
  beforeEach(() => ((mock = RUNTIME.mockApi), (RUNTIME.mockApi = false)));
  afterEach(() => (RUNTIME.mockApi = mock));

  function setup() {
    TestBed.configureTestingModule({ providers: [provideHttpClient(), provideHttpClientTesting()] });
    return { svc: TestBed.inject(PlansService), http: TestBed.inject(HttpTestingController) };
  }

  it('starts from the build-time snapshot, whatever it contains (the build refreshes it)', () => {
    const { svc } = setup();
    expect(svc.plans()).toEqual(parsePlans(snapshot));
    expect(svc.serviceLabels()).toEqual([...new Set(parsePlans(snapshot).map((p) => p.serviceLabel).filter(Boolean))]);
  });

  it('replaces the catalog with a valid answer, once', () => {
    const { svc, http } = setup();
    svc.refresh();
    svc.refresh();
    http.expectOne((r) => r.url.endsWith('/v6/plans') && r.method === 'POST' && JSON.stringify(r.body) === '{}').flush([api()]);
    expect(svc.plans().map((p) => p.key)).toEqual(['vps-1']);
    expect(svc.serviceLabels()).toEqual(['Renta de Servidores VPS']);
    http.verify();
  });

  it('keeps the prerendered catalog on failure or malformed answers', () => {
    const { svc, http } = setup();
    svc.plans.set(parsePlans([api()]));
    svc.refresh();
    http.expectOne((r) => r.url.endsWith('/v6/plans')).flush('boom', { status: 500, statusText: 'err' });
    expect(svc.plans()).toHaveLength(1);
    http.verify();
  });
});
