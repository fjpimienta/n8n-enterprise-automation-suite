import { TestBed, ComponentFixture } from '@angular/core/testing';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { TenantService } from 'core-auth';
import { CattleApiService } from '@core/services/cattle-api.service';
import { ProductionUnitLotService } from '@features/admin/services/production-unit-lot.service';
import { PanelLivestockResponse } from '../../../models/panel-livestock.model';
import { todayInMexicoCity } from '../../../panel-livestock.util';
import {
  CattleDetailModalComponent,
  PANEL_FORBIDDEN_MESSAGE,
  PANEL_NO_TENANT_MESSAGE,
  PANEL_UNCERTAIN_SAVE_MESSAGE
} from './cattle-detail-modal.component';

const PREVIEW: PanelLivestockResponse = {
  status: 'preview',
  preview: { empresa: 'Rancho Demo', upp: 'Norte', arete: '9821100005', categoria: 'VACA' },
  preview_hash: 'hash-1',
  warnings: [{ type: 'no_official_tag', message: 'El animal no tiene arete oficial.' }]
};
const RECORDED: PanelLivestockResponse = { status: 'recorded', livestock_id: 'abc-123', message: 'Animal registrado.' };

function deferred<T>() {
  let resolve!: (v: T) => void;
  const promise = new Promise<T>(r => (resolve = r));
  return { promise, resolve };
}

describe('CattleDetailModalComponent — ALTA', () => {
  let api: { registerLivestockPanel: ReturnType<typeof vi.fn>; createLivestock: ReturnType<typeof vi.fn> };
  let fixture: ComponentFixture<CattleDetailModalComponent>;
  let component: CattleDetailModalComponent;
  let role: string | undefined;
  let tenantId: string | null;
  let units: any[];

  function create() {
    fixture = TestBed.createComponent(CattleDetailModalComponent);
    component = fixture.componentInstance;
    component.actionType = 'ALTA';
    fixture.detectChanges();
    return component;
  }
  const el = () => fixture.nativeElement as HTMLElement;
  const tid = (id: string) => el().querySelector(`[data-testid="${id}"]`) as HTMLElement | null;

  beforeEach(() => {
    role = 'EDITOR';
    tenantId = '3';
    units = [{ isActive: true, uppCode: '99-821-0000-001', ranchName: 'Norte' }, { isActive: false, uppCode: '99-821-0000-009', ranchName: 'Vieja' }];
    api = { registerLivestockPanel: vi.fn(), createLivestock: vi.fn().mockResolvedValue({}) };
    TestBed.configureTestingModule({
      providers: [
        { provide: CattleApiService, useValue: api },
        { provide: TenantService, useValue: { activeTenant: () => ({ role }), activeTenantId: () => tenantId } },
        { provide: ProductionUnitLotService, useValue: { getProductionUnits: () => Promise.resolve(units) } }
      ]
    });
    vi.spyOn(window, 'alert').mockImplementation(() => {});
  });
  afterEach(() => {
    vi.useRealTimers();
    vi.restoreAllMocks();
  });

  describe('tenant not allow-listed', () => {
    it('keeps the legacy form and createLivestock', async () => {
      tenantId = '5';
      create();
      expect(tid('panel-alta')).toBeNull();
      expect(el().querySelector('input[formcontrolname="rfid_siniiga"]')).not.toBeNull();
      component.altaForm.patchValue({ current_weight_kg: 400 });
      await component.submitForm();
      expect(api.createLivestock).toHaveBeenCalledTimes(1);
      expect(api.registerLivestockPanel).not.toHaveBeenCalled();
    });

    it('tenant 5 (not allow-listed) gets the legacy form and the legacy submit path', async () => {
      tenantId = '5';
      create();
      expect(component.panelFlow).toBe(false);
      expect(tid('panel-alta')).toBeNull();
      component.altaForm.patchValue({ current_weight_kg: 400 });
      await component.submitForm();
      expect(api.createLivestock).toHaveBeenCalledTimes(1);
      expect(api.registerLivestockPanel).not.toHaveBeenCalled();
    });

    it('no active tenant never gets the new flow', () => {
      tenantId = null;
      create();
      expect(component.panelFlow).toBe(false);
      expect(component.phase()).toBe('editing');
      expect(tid('panel-alta')).toBeNull();
    });
  });

  describe('tenant 3 — step 1', () => {
    it('starts empty-tag, with today in CDMX, and loads only active UPPs', async () => {
      vi.useFakeTimers({ toFake: ['Date'] });
      vi.setSystemTime(new Date('2026-11-11T02:30:00Z')); // evening of the 10th in CDMX
      create();
      await fixture.whenStable();
      expect(component.panelForm.value.ear_tag).toBe('');
      expect(component.panelForm.value.birth_date).toBe('2026-11-10');
      expect(component.panelForm.value.birth_date).toBe(todayInMexicoCity());
      expect(component.uppOptions()).toEqual([{ value: '99-821-0000-001', label: 'Norte (99-821-0000-001)' }]);
      expect(tid('panel-alta')).not.toBeNull();
    });

    it('blocks the flow when the active tenant disappears after opening', async () => {
      create();
      expect(component.panelFlow).toBe(true);
      tenantId = null;
      await component.review();
      expect(component.phase()).toBe('error');
      expect(component.error()).toBe(PANEL_NO_TENANT_MESSAGE);
      expect(api.registerLivestockPanel).not.toHaveBeenCalled();
    });

    it('does not pass id_company from the form', async () => {
      create();
      api.registerLivestockPanel.mockResolvedValue(PREVIEW);
      await component.review();
      const input = api.registerLivestockPanel.mock.calls[0][0];
      expect(Object.keys(input)).not.toContain('id_company');
      expect(Object.keys(input)).not.toContain('tenant_id');
    });

    it('a role outside ADMIN/EDITOR gets the forbidden message and no call', async () => {
      role = 'OWNER';
      create();
      expect(component.phase()).toBe('blocked');
      expect(component.blockMessage()).toBe(PANEL_FORBIDDEN_MESSAGE);
      await component.review();
      expect(api.registerLivestockPanel).not.toHaveBeenCalled();
    });

    it('shows a weight validation error inline and stays in step 1', async () => {
      create();
      component.panelForm.patchValue({ weight_kg: 'abc' });
      await component.review();
      expect(api.registerLivestockPanel).not.toHaveBeenCalled();
      expect(component.phase()).toBe('editing');
      fixture.detectChanges();
      expect(tid('panel-weight-error')?.textContent).toContain('El peso debe ser un número');
      expect(window.alert).not.toHaveBeenCalled();
    });
  });

  describe('status handling', () => {
    beforeEach(() => create());

    it('preview → step 2 with summary and warning messages, confirm sends the hash', async () => {
      api.registerLivestockPanel.mockResolvedValueOnce(PREVIEW).mockResolvedValueOnce(RECORDED);
      await component.review();
      expect(api.registerLivestockPanel.mock.calls[0][1]).toBeUndefined();
      expect(component.phase()).toBe('previewing');
      fixture.detectChanges();
      expect(tid('panel-preview')?.textContent).toContain('Rancho Demo');
      expect(tid('panel-warnings')?.textContent).toContain('El animal no tiene arete oficial.');
      await component.confirm();
      expect(api.registerLivestockPanel.mock.calls[1][1]).toEqual({ confirm: true, previewHash: 'hash-1' });
    });

    it('preview_required shows the new preview and asks to confirm again', async () => {
      api.registerLivestockPanel.mockResolvedValueOnce(PREVIEW).mockResolvedValueOnce({
        ...PREVIEW, status: 'preview_required', preview_hash: 'hash-2', message: 'Los datos cambiaron.'
      });
      await component.review();
      await component.confirm();
      expect(component.phase()).toBe('previewing');
      expect(component.previewNotice()).toBe('Los datos cambiaron.');
      api.registerLivestockPanel.mockResolvedValueOnce(RECORDED);
      await component.confirm();
      expect(api.registerLivestockPanel.mock.calls[2][1]).toEqual({ confirm: true, previewHash: 'hash-2' });
    });

    it('recorded → success and close(true)', async () => {
      const closed: boolean[] = [];
      component.close.subscribe(v => closed.push(v));
      api.registerLivestockPanel.mockResolvedValueOnce(PREVIEW).mockResolvedValueOnce(RECORDED);
      await component.review();
      await component.confirm();
      expect(component.phase()).toBe('saved');
      expect(component.success()).toBe('Animal registrado.');
      expect(closed).toEqual([true]);
    });

    it('recorded without livestock_id is an error, never success', async () => {
      const closed: boolean[] = [];
      component.close.subscribe(v => closed.push(v));
      api.registerLivestockPanel.mockResolvedValueOnce(PREVIEW).mockResolvedValueOnce({ status: 'recorded' });
      await component.review();
      await component.confirm();
      expect(component.phase()).toBe('error');
      expect(component.success()).toBeNull();
      expect(closed).toEqual([]);
    });

    it('need_info stays in step 1, shows issues next to the field and the UPP options', async () => {
      api.registerLivestockPanel.mockResolvedValue({
        status: 'need_info',
        issues: [
          { type: 'ambiguous', field: 'upp', message: 'Indica la UPP.', options: [{ upp: 'Norte', upp_code: '99-821-0000-001' }, { upp: 'Sur', upp_code: '99-821-0000-002' }] },
          { type: 'invalid', field: 'birth_date', message: 'La fecha no puede ser futura.' }
        ]
      });
      await component.review();
      fixture.detectChanges();
      expect(component.phase()).toBe('editing');
      expect(el().textContent).toContain('La fecha no puede ser futura.');
      expect(el().textContent).toContain('Indica la UPP.');
      expect(tid('panel-upp-options')?.textContent).toContain('Sur (99-821-0000-002)');
      component.pickUpp('99-821-0000-002');
      expect(component.panelForm.value.upp).toBe('99-821-0000-002');
      expect(component.issueFor('upp')).toBeUndefined();
    });

    it.each(['duplicate', 'duplicate_other_company', 'exists_without_upp'] as const)(
      '%s blocks with the existing animal and NO force button',
      async status => {
        api.registerLivestockPanel.mockResolvedValue({
          status, message: 'Ese arete ya existe.', category: 'VACA', current_status: 'ACTIVO', upp: 'Norte'
        });
        await component.review();
        fixture.detectChanges();
        expect(component.phase()).toBe('blocked');
        expect(tid('panel-blocked')?.textContent).toContain('Ese arete ya existe.');
        expect(tid('panel-existing')?.textContent).toContain('VACA');
        expect(tid('panel-force')).toBeNull();
        await component.registerAnyway();
        expect(api.registerLivestockPanel).toHaveBeenCalledTimes(1);
      }
    );

    it('duplicate_recent offers "Registrar de todos modos", re-sent with force and the current hash', async () => {
      api.registerLivestockPanel
        .mockResolvedValueOnce(PREVIEW)
        .mockResolvedValueOnce({ status: 'duplicate_recent', message: 'Se registró hace menos de 2 minutos.', livestock_id: 'x', preview: PREVIEW.preview })
        .mockResolvedValueOnce(RECORDED);
      await component.review();
      await component.confirm();
      fixture.detectChanges();
      expect(component.phase()).toBe('blocked');
      expect(tid('panel-force')?.textContent).toContain('Registrar de todos modos');
      expect(tid('panel-existing')?.textContent).toContain('Rancho Demo');
      expect(tid('panel-existing')?.textContent).toContain('9821100005');
      await component.registerAnyway();
      expect(api.registerLivestockPanel.mock.calls[2][1]).toEqual({ confirm: true, previewHash: 'hash-1', forceDuplicate: true });
      expect(component.phase()).toBe('saved');
    });

    it('forbidden shows the clear role message', async () => {
      api.registerLivestockPanel.mockResolvedValue({ status: 'forbidden', message: 'x' });
      await component.review();
      fixture.detectChanges();
      expect(tid('panel-blocked')?.textContent).toContain('Tu rol no permite dar de alta animales.');
    });

    it.each(['palm', 'invalid'] as const)('%s shows the message and stays in step 1', async status => {
      api.registerLivestockPanel.mockResolvedValue({ status, message: 'Mensaje del servidor.' });
      await component.review();
      fixture.detectChanges();
      expect(component.phase()).toBe('editing');
      expect(tid('panel-form-message')?.textContent).toContain('Mensaje del servidor.');
    });

    it.each([
      ['empty response', () => Promise.reject(new Error('El servidor no confirmó el alta del animal.'))],
      ['data:null / error=true / unknown status (service throws)', () => Promise.reject(new Error('Respuesta inesperada del servidor al registrar el animal.'))],
      ['unknown status slipping through', () => Promise.resolve({ status: 'weird' } as any)],
      ['null response', () => Promise.resolve(null as any)]
    ])('%s → error state, never success', async (_name, impl) => {
      const closed: boolean[] = [];
      component.close.subscribe(v => closed.push(v));
      api.registerLivestockPanel.mockImplementation(impl);
      await component.review();
      expect(component.phase()).toBe('error');
      expect(component.error()).toBeTruthy();
      expect(component.success()).toBeNull();
      expect(closed).toEqual([]);
    });

    it('a weight with a decimal comma passes the local validation', async () => {
      api.registerLivestockPanel.mockResolvedValue(PREVIEW);
      component.panelForm.patchValue({ weight_kg: '412,5' });
      await component.review();
      expect(component.phase()).toBe('previewing');
    });

    it('a service error mentioning "peso" is not treated as a field error', async () => {
      api.registerLivestockPanel.mockRejectedValue(new Error('Error del peso en el servidor'));
      await component.review();
      expect(component.phase()).toBe('error');
      expect(component.fieldErrors()).toEqual({});
    });

    it.each([
      ['throws', () => Promise.reject(new Error('timeout'))],
      ['empty response', () => Promise.resolve(null as any)],
      ['recorded without id', () => Promise.resolve({ status: 'recorded' } as any)]
    ])('confirm that %s shows the uncertain-save message and keeps the form', async (_n, impl) => {
      api.registerLivestockPanel.mockResolvedValueOnce(PREVIEW).mockImplementationOnce(impl);
      component.panelForm.patchValue({ lot: 'L-7', notes: 'hola' });
      await component.review();
      await component.confirm();
      expect(component.phase()).toBe('error');
      expect(component.error()).toBe(PANEL_UNCERTAIN_SAVE_MESSAGE);
      expect(component.success()).toBeNull();
      component.backToEditing();
      expect(component.panelForm.value.lot).toBe('L-7');
      expect(component.panelForm.value.notes).toBe('hola');
    });

    it('general issues use a human field label', async () => {
      api.registerLivestockPanel.mockResolvedValue({
        status: 'need_info', issues: [{ type: 'invalid', field: 'tenant_id', message: 'Falta.' }]
      });
      await component.review();
      fixture.detectChanges();
      expect(tid('panel-general-issues')?.textContent).toContain('Empresa: Falta.');
      expect(tid('panel-general-issues')?.textContent).not.toContain('tenant_id');
    });

    it('an error while confirming drops the preview hash (no confirm without a new preview)', async () => {
      api.registerLivestockPanel.mockResolvedValueOnce(PREVIEW).mockRejectedValueOnce(new Error('boom'));
      await component.review();
      await component.confirm();
      expect(component.phase()).toBe('error');
      component.backToEditing();
      await component.confirm();
      expect(api.registerLivestockPanel).toHaveBeenCalledTimes(2);
    });
  });

  describe('double-click guard', () => {
    beforeEach(() => create());

    it('review() ignores a second call while the first is in flight', async () => {
      const d = deferred<PanelLivestockResponse>();
      api.registerLivestockPanel.mockReturnValue(d.promise);
      const first = component.review();
      const second = component.review();
      expect(component.isSubmitting()).toBe(true);
      expect(component.phase()).toBe('checking');
      d.resolve(PREVIEW);
      await Promise.all([first, second]);
      expect(api.registerLivestockPanel).toHaveBeenCalledTimes(1);
      expect(component.isSubmitting()).toBe(false);
    });

    it('confirm() ignores a second call while saving', async () => {
      api.registerLivestockPanel.mockResolvedValueOnce(PREVIEW);
      await component.review();
      const d = deferred<PanelLivestockResponse>();
      api.registerLivestockPanel.mockReturnValue(d.promise);
      const first = component.confirm();
      const second = component.confirm();
      expect(component.phase()).toBe('saving');
      d.resolve(RECORDED);
      await Promise.all([first, second]);
      expect(api.registerLivestockPanel).toHaveBeenCalledTimes(2);
    });

    it('registerAnyway() ignores a second call while saving', async () => {
      api.registerLivestockPanel
        .mockResolvedValueOnce(PREVIEW)
        .mockResolvedValueOnce({ status: 'duplicate_recent', message: 'm' });
      await component.review();
      await component.confirm();
      const d = deferred<PanelLivestockResponse>();
      api.registerLivestockPanel.mockReturnValue(d.promise);
      const first = component.registerAnyway();
      const second = component.registerAnyway();
      d.resolve(RECORDED);
      await Promise.all([first, second]);
      expect(api.registerLivestockPanel).toHaveBeenCalledTimes(3);
    });

    it('does not fall into the legacy createLivestock', async () => {
      await component.submitForm();
      expect(api.createLivestock).not.toHaveBeenCalled();
    });
  });
});
