import { signal } from '@angular/core';
import { TestBed } from '@angular/core/testing';
import { HttpErrorResponse } from '@angular/common/http';
import { AuthService, SessionScope, TenantService } from 'core-auth';
import { CattleApiService } from './cattle-api.service';
import { CattleDataService } from './cattle-data.service';
import { OfflineStoreService } from './offline-store.service';

const S1: SessionScope = { user: 'ana', id_company: 1 };
const S2: SessionScope = { user: 'ana', id_company: 2 };
const SAVED = '2026-11-16T10:00:00.000Z';

const liveRow = (tenant = 1) => ({
  id: 'a1', tenant_id: tenant, rfid_siniiga: '1234567890',
  metadata: { purchase_price: 100, seller_name: 'Z', purchase_date: 'd', nota_venta: 'n', registered_by: 'r',
    venta_registrada_solo_en_libreta: true, notes: 'n', note: 'n', observaciones: 'o', nota_transcripcion: 't', caracteristicas: 'c', other: 1 }
});

describe('CattleDataService offline read-through', () => {
  let scope: SessionScope | null;
  let state: 'valid' | 'grace' | 'expired';
  let tenantId: ReturnType<typeof signal<string | null>>;
  let api: { getAllLivestock: ReturnType<typeof vi.fn> };
  let store: { put: ReturnType<typeof vi.fn>; get: ReturnType<typeof vi.fn> };
  let svc: CattleDataService;

  async function init(): Promise<void> {
    TestBed.resetTestingModule();
    TestBed.configureTestingModule({
      providers: [
        { provide: CattleApiService, useValue: api },
        { provide: TenantService, useValue: { activeTenantId: tenantId } },
        { provide: AuthService, useValue: { getSessionScope: () => scope, getSessionState: () => state } },
        { provide: OfflineStoreService, useValue: store }
      ]
    });
    svc = TestBed.inject(CattleDataService);
  }

  async function load(): Promise<void> {
    api.getAllLivestock.mockClear();
    store.put.mockClear();
    store.get.mockClear();
    await svc.loadCattleData();
  }

  beforeEach(async () => {
    scope = S1;
    state = 'valid';
    tenantId = signal<string | null>(null); // keep the constructor effect idle
    api = { getAllLivestock: vi.fn().mockResolvedValue([liveRow()]) };
    store = { put: vi.fn().mockResolvedValue(true), get: vi.fn().mockResolvedValue(null) };
    vi.spyOn(console, 'error').mockImplementation(() => undefined);
    vi.spyOn(console, 'warn').mockImplementation(() => undefined);
    await init();
  });

  afterEach(() => vi.restoreAllMocks());

  it('valid + success stores sanitized data under the scope captured at start', async () => {
    await load();
    expect(svc.cattleList().length).toBe(1);
    expect(svc.servedFromCache()).toBe(false);
    expect(store.put).toHaveBeenCalledTimes(1);
    const [dataset, data, usedScope] = store.put.mock.calls[0];
    expect(dataset).toBe('livestock');
    expect(usedScope).toEqual(S1);
    expect(data).toEqual([{ id: 'a1', tenant_id: 1, rfid_siniiga: '1234567890', metadata: null }]);
  });

  it('no metadata key (denylisted or not) ever reaches offlineStore.put', async () => {
    await load();
    const stored = JSON.stringify(store.put.mock.calls);
    for (const key of ['purchase_price', 'seller_name', 'purchase_date', 'nota_venta', 'registered_by',
      'venta_registrada_solo_en_libreta', 'notes', 'note', 'observaciones', 'nota_transcripcion', 'caracteristicas', 'other']) {
      expect(stored).not.toContain(key);
    }
  });

  it('skips the put when the scope is null', async () => {
    scope = null;
    await load();
    expect(svc.cattleList().length).toBe(1);
    expect(store.put).not.toHaveBeenCalled();
  });

  it('a failed or rejected put is silent', async () => {
    store.put.mockRejectedValue(new Error('idb'));
    await load();
    expect(svc.loadError()).toBeNull();
    expect(svc.cattleList().length).toBe(1);
    store.put.mockImplementation(() => { throw new Error('sync'); });
    await load();
    expect(svc.loadError()).toBeNull();
  });

  it('tenant switch between request and response stores nothing and shows nothing stale', async () => {
    let resolve!: (v: any[]) => void;
    api.getAllLivestock.mockImplementationOnce(() => new Promise(r => { resolve = r; }));
    store.put.mockClear();
    const p = svc.loadCattleData();
    scope = S2; // switch while in flight
    resolve([liveRow(1)]);
    await p;
    expect(svc.cattleList()).toEqual([]);
    expect(store.put).not.toHaveBeenCalled();
  });

  it('latest wins: an older response never overwrites or is stored after a newer call', async () => {
    let resolveOld!: (v: any[]) => void;
    api.getAllLivestock
      .mockImplementationOnce(() => new Promise(r => { resolveOld = r; }))
      .mockResolvedValueOnce([{ id: 'new', tenant_id: 1 }]);
    store.put.mockClear();
    const old = svc.loadCattleData();
    await svc.loadCattleData();
    resolveOld([{ id: 'old', tenant_id: 1 }]);
    await old;
    expect(svc.cattleList()[0].id).toBe('new');
    expect(store.put).toHaveBeenCalledTimes(1);
  });

  it('valid + network failure (status 0) serves the cache', async () => {
    api.getAllLivestock.mockRejectedValue(new HttpErrorResponse({ status: 0 }));
    store.get.mockResolvedValue({ data: [{ id: 'c1', tenant_id: 1, metadata: null }], savedAt: SAVED });
    await load();
    expect(svc.cattleList()[0].id).toBe('c1');
    expect(svc.servedFromCache()).toBe(true);
    expect(svc.cacheSavedAt()).toBe(SAVED);
    expect(svc.loadError()).toBeNull();
  });

  it('valid + network failure without snapshot keeps today\'s error behavior', async () => {
    await load(); // good data first
    api.getAllLivestock.mockRejectedValue(new HttpErrorResponse({ status: 0 }));
    await load();
    expect(svc.loadError()).toBeTruthy();
    expect(svc.cattleList().length).toBe(1);
    expect(svc.servedFromCache()).toBe(false);
  });

  it('a successful live load resets the cache flags', async () => {
    api.getAllLivestock.mockRejectedValueOnce(new HttpErrorResponse({ status: 0 }));
    store.get.mockResolvedValue({ data: [{ id: 'c1', tenant_id: 1 }], savedAt: SAVED });
    await load();
    expect(svc.servedFromCache()).toBe(true);
    await load();
    expect(svc.servedFromCache()).toBe(false);
    expect(svc.cacheSavedAt()).toBeNull();
  });

  it('valid + gateway error:true does NOT serve the cache', async () => {
    vi.spyOn(navigator, 'onLine', 'get').mockReturnValue(true);
    api.getAllLivestock.mockRejectedValue(new Error('gateway error'));
    store.get.mockResolvedValue({ data: [{ id: 'c1', tenant_id: 1 }], savedAt: SAVED });
    await load();
    expect(store.get).not.toHaveBeenCalled();
    expect(svc.servedFromCache()).toBe(false);
    expect(svc.loadError()).toBe('gateway error');
  });

  it('valid + HTTP 500 does NOT serve the cache', async () => {
    vi.spyOn(navigator, 'onLine', 'get').mockReturnValue(true);
    api.getAllLivestock.mockRejectedValue(new HttpErrorResponse({ status: 500 }));
    store.get.mockResolvedValue({ data: [{ id: 'c1', tenant_id: 1 }], savedAt: SAVED });
    await load();
    expect(store.get).not.toHaveBeenCalled();
    expect(svc.servedFromCache()).toBe(false);
    expect(svc.loadError()).toBeTruthy();
  });

  it('grace makes zero HTTP calls and serves the cache', async () => {
    state = 'grace';
    store.get.mockResolvedValue({ data: [{ id: 'c1', tenant_id: 1 }], savedAt: SAVED });
    await load();
    expect(api.getAllLivestock).not.toHaveBeenCalled();
    expect(svc.cattleList()[0].id).toBe('c1');
    expect(svc.servedFromCache()).toBe(true);
    expect(store.put).not.toHaveBeenCalled();
  });

  it('grace without snapshot sets a clear error and an empty list, with zero HTTP', async () => {
    state = 'grace';
    await load();
    expect(api.getAllLivestock).not.toHaveBeenCalled();
    expect(svc.cattleList()).toEqual([]);
    expect(svc.loadError()).toContain('Sin conexión');
    expect(svc.servedFromCache()).toBe(false);
  });

  it('expired uses the HTTP path and never reads or writes the cache', async () => {
    state = 'expired';
    await load();
    expect(api.getAllLivestock).toHaveBeenCalledTimes(1);
    expect(store.get).not.toHaveBeenCalled();
    expect(store.put).not.toHaveBeenCalled();
    api.getAllLivestock.mockRejectedValue(new HttpErrorResponse({ status: 0 }));
    await load();
    expect(store.get).not.toHaveBeenCalled();
    expect(svc.servedFromCache()).toBe(false);
  });

  it('a snapshot with any row from another tenant is discarded whole', async () => {
    state = 'grace';
    store.get.mockResolvedValue({ data: [{ id: 'ok', tenant_id: 1 }, { id: 'bad', tenant_id: 2 }], savedAt: SAVED });
    await load();
    expect(svc.cattleList()).toEqual([]);
    expect(svc.servedFromCache()).toBe(false);
    expect(svc.loadError()).toBeTruthy();
  });

  it('a tenant mismatch log carries no data contents', async () => {
    const warn = vi.spyOn(console, 'warn');
    state = 'grace';
    store.get.mockResolvedValue({ data: [{ id: 'SECRET-ID', tenant_id: 2, rfid_siniiga: 'SECRET-RFID' }], savedAt: SAVED });
    await load();
    expect(JSON.stringify(warn.mock.calls)).not.toContain('SECRET');
  });
});
