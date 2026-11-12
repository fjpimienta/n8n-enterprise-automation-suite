import { TestBed } from '@angular/core/testing';
import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TenantService } from 'core-auth';
import { environment } from '@env/environment';
import { CattleApiService } from './cattle-api.service';
import { LoggerService } from './logger.service';
import { PANEL_LIVESTOCK_STATUSES } from '@features/livestock/models/panel-livestock.model';

const WARNINGS = [
  {
    type: 'no_official_tag', field: 'ear_tag',
    message: 'Sin arete oficial: el animal se registrará con un identificador interno (S/N-…) y NO podrá venderse ni darse de salida hasta que tenga un arete SINIIGA de 10 dígitos.'
  },
  {
    type: 'tb_missing_or_expired', field: 'tb_test_date',
    message: 'Prueba TB no registrada: la venta o salida de este animal se bloqueará hasta registrarla (salvo dictamen de hato libre de la UPP).'
  }
];

describe('CattleApiService.registerLivestockPanel', () => {
  let service: CattleApiService;
  let http: HttpTestingController;
  const url = `${environment.apiUrl_crud}/register_livestock_panel`;

  beforeEach(() => {
    TestBed.configureTestingModule({
      providers: [
        provideHttpClient(),
        provideHttpClientTesting(),
        { provide: TenantService, useValue: { activeTenantId: () => '3' } },
        { provide: LoggerService, useValue: { warn: () => {}, error: () => {}, log: () => {} } }
      ]
    });
    service = TestBed.inject(CattleApiService);
    http = TestBed.inject(HttpTestingController);
  });

  afterEach(() => http.verify());

  async function call(input: any, opts: any, reply: any) {
    const p = service.registerLivestockPanel(input, opts);
    const req = http.expectOne(url);
    req.flush(reply);
    return { req, result: p };
  }

  it('posts the exact URL and body for a preview, all values as strings, no tenant or e-mail', async () => {
    const { req, result } = await call(
      { upp: 'UPP1', category: 'VACA', ear_tag: '1234567890', weight_kg: 450, notes: ' x ' },
      undefined,
      { data: { status: 'preview', preview_hash: 'h' } }
    );
    await result;
    expect(req.request.method).toBe('POST');
    expect(req.request.body).toEqual({
      operation: 'call_sp',
      fields: {
        upp: 'UPP1', lot: '', species: '', category: 'VACA', business_model: '', ear_tag: '1234567890',
        fire_number: '', electronic_rfid: '', weight_kg: '450', birth_date: '', origin_upp: '',
        tb_test_date: '', br_test_date: '', notes: 'x',
        confirmed: '', preview_hash: '', force_duplicate: ''
      }
    });
    const f = req.request.body.fields;
    expect('tenant_id' in f || 'actor_email' in f).toBe(false);
    expect('tenant_id' in req.request.body).toBe(false);
    expect(Object.values(f).every(v => typeof v === 'string')).toBe(true);
  });

  it('normalizes the decimal comma and strips spaces in the weight', async () => {
    const { req, result } = await call({ weight_kg: ' 412,5 ' }, {}, { data: { status: 'preview' } });
    await result;
    expect(req.request.body.fields.weight_kg).toBe('412.5');
  });

  it('rejects a non-numeric weight without calling the server', async () => {
    for (const bad of ['abc', '1,234.5', '-5', '12kg']) {
      await expect(service.registerLivestockPanel({ weight_kg: bad })).rejects.toThrow(/peso/i);
    }
    http.expectNone(url);
  });

  it('rejects a confirmation without previewHash', async () => {
    await expect(service.registerLivestockPanel({}, { confirm: true })).rejects.toThrow();
    http.expectNone(url);
  });

  it('sends confirmed true and the hash on confirmation; hash ignored without confirm', async () => {
    const a = await call({}, { confirm: true, previewHash: 'abc' }, { data: { status: 'recorded', livestock_id: '1' } });
    await a.result;
    expect(a.req.request.body.fields.confirmed).toBe('true');
    expect(a.req.request.body.fields.preview_hash).toBe('abc');
    const b = await call({}, { confirm: false, previewHash: 'abc' }, { data: { status: 'preview' } });
    await b.result;
    expect(b.req.request.body.fields.confirmed).toBe('');
    expect(b.req.request.body.fields.preview_hash).toBe('');
  });

  it('sends force_duplicate true only when requested', async () => {
    const a = await call({}, { confirm: true, previewHash: 'h', forceDuplicate: true }, { data: { status: 'recorded' } });
    await a.result;
    expect(a.req.request.body.fields.force_duplicate).toBe('true');
  });

  it('returns every known status typed, warnings included', async () => {
    for (const status of PANEL_LIVESTOCK_STATUSES) {
      const { result } = await call({}, {}, { data: { status, warnings: WARNINGS, message: 'm' } });
      const r = await result;
      expect(r.status).toBe(status);
      expect(r.warnings).toEqual(WARNINGS);
    }
  });

  it('keeps type, field and message of every warning object', async () => {
    const { result } = await call({}, {}, { data: { status: 'preview', warnings: WARNINGS } });
    const warnings = (await result).warnings!;
    expect(warnings.length).toBe(2);
    for (const [i, w] of warnings.entries()) {
      expect(typeof w).toBe('object');
      expect(w.type).toBe(WARNINGS[i].type);
      expect(w.field).toBe(WARNINGS[i].field);
      expect(w.message).toBe(WARNINGS[i].message);
    }
  });

  it('keeps need_info issues intact', async () => {
    const issue = { type: 'ambiguous', field: 'upp', message: 'm', options: ['A', 'B'], code: 'c' };
    const { result } = await call({}, {}, { data: { status: 'need_info', issues: [issue] } });
    expect((await result).issues).toEqual([issue]);
  });

  it('throws on empty response, null data, error=true and unknown status', async () => {
    for (const reply of [null, '', {}, { data: null }, { error: true, message: 'boom', data: { status: 'recorded' } },
                         { data: { status: 'saved' } }, { data: { status: 'recorded' }, error: true }, { data: {} }]) {
      const { result } = await call({}, {}, reply);
      await expect(result).rejects.toThrow();
    }
  });

  it('does not retry on a failed call', async () => {
    const p = service.registerLivestockPanel({}, { confirm: true, previewHash: 'h' });
    http.expectOne(url).flush('x', { status: 500, statusText: 'err' });
    await expect(p).rejects.toBeTruthy();
    http.expectNone(url);
  });
});

describe('CattleApiService.createLivestock (unchanged)', () => {
  it('still inserts directly into cattle_livestock', async () => {
    TestBed.configureTestingModule({
      providers: [
        provideHttpClient(), provideHttpClientTesting(),
        { provide: TenantService, useValue: { activeTenantId: () => '3' } },
        { provide: LoggerService, useValue: { warn: () => {}, error: () => {}, log: () => {} } }
      ]
    });
    const service = TestBed.inject(CattleApiService);
    const http = TestBed.inject(HttpTestingController);
    const p = service.createLivestock({ rfid_siniiga: 'X' } as any);
    const req = http.expectOne(`${environment.apiUrl_crud}/cattle_livestock`);
    expect(req.request.body.operation).toBe('insert');
    expect(req.request.body.fields.tenant_id).toBe(3);
    req.flush({ data: [{}] });
    await p.catch(() => {});
    http.verify();
  });
});
