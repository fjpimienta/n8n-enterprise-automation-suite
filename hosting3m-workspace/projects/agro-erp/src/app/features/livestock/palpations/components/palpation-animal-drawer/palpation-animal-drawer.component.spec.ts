import { ComponentFixture, TestBed } from '@angular/core/testing';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { PalpationEventRow, ReportErrorReason } from '../../models/palpation.types';
import { PalpationReportService } from '../../services/palpation-report.service';
import { eventRow } from '../../testing/palpation.fixtures';
import { PalpationTableRow } from '../../utils/palpation-view';
import { PalpationAnimalDrawerComponent } from './palpation-animal-drawer.component';

const animal: PalpationTableRow = {
  livestockId: 'an-1', identifier: '9999000001', category: 'VACA', currentStatus: 'ACTIVO', lastDate: '2026-11-10',
  state: 'VACÍA', subtype: 'ESTATICA', ranchTerm: null, gestation: null, technician: null, unconfirmedCode: null,
  historical: false, uninterpreted: false,
};

type History = { ok: true; rows: PalpationEventRow[] } | { ok: false; reason: ReportErrorReason };

function setup(history: History | Promise<History>, opener: HTMLElement | null = null): ComponentFixture<PalpationAnimalDrawerComponent> {
  const fake = { loadHistory: vi.fn(() => Promise.resolve(history)) };
  TestBed.configureTestingModule({ providers: [{ provide: PalpationReportService, useValue: fake }] });
  const f = TestBed.createComponent(PalpationAnimalDrawerComponent);
  f.componentRef.setInput('animal', animal);
  f.componentRef.setInput('opener', opener);
  f.detectChanges();
  return f;
}
async function settled(f: ComponentFixture<unknown>): Promise<void> {
  await f.whenStable();
  f.detectChanges();
}
const el = (f: ComponentFixture<unknown>) => f.nativeElement as HTMLElement;
const text = (f: ComponentFixture<unknown>) => el(f).textContent?.replace(/\s+/g, ' ').trim() ?? '';
const key = (target: Element, k: string, shift = false) => {
  const ev = new KeyboardEvent('keydown', { key: k, shiftKey: shift, bubbles: true, cancelable: true });
  target.dispatchEvent(ev);
  return ev;
};

const two = [
  eventRow({ livestock_id: 'an-1', health_log_id: 'e1', event_date: '2026-10-01', result: 'VACÍA', repro_condition: 'CICLANDO', mapping_status: 'EXPLICIT' }),
  eventRow({ livestock_id: 'an-1', health_log_id: 'e2', event_date: '2026-11-05', result: 'PREÑADA', gestation_days: 60, technician: 'Técnico sintético' }),
];

afterEach(() => {
  document.body.classList.remove('modal-open');
});

describe('PalpationAnimalDrawerComponent', () => {
  it('is a modal dialog: role, aria-modal and a title that labels it', async () => {
    const f = setup({ ok: true, rows: two });
    await settled(f);
    const dialog = el(f).querySelector('[role="dialog"]')!;
    expect(dialog.getAttribute('aria-modal')).toBe('true');
    const labelId = dialog.getAttribute('aria-labelledby')!;
    expect(el(f).querySelector(`#${labelId}`)?.textContent).toContain('Historial de palpaciones');
    expect(text(f)).toContain('9999000001 · VACA');
  });

  it('moves the focus into the dialog (the close button) when it opens', async () => {
    const f = setup({ ok: true, rows: two });
    await settled(f);
    expect(document.activeElement).toBe(el(f).querySelector('.btn-close'));
  });

  it('shows the loading state first', () => {
    const f = setup(new Promise<History>(() => undefined));
    expect(text(f)).toContain('Cargando historial');
    expect(el(f).querySelector('[aria-busy="true"]')).not.toBeNull();
  });

  it('lists the events newest first, with the latest labelled and the previous one below', async () => {
    const f = setup({ ok: true, rows: two });
    await settled(f);
    const items = [...el(f).querySelectorAll('[data-testid="timeline"] li')].map(li => li.textContent?.replace(/\s+/g, ' ').trim() ?? '');
    expect(items.length).toBe(2);
    expect(items[0]).toContain('05/11/2026');
    expect(items[0]).toContain('Más reciente');
    expect(items[0]).toContain('Preñada');
    expect(items[0]).toContain('2,0 meses (60 días)');
    expect(items[0]).toContain('Técnico: Técnico sintético');
    expect(items[1]).toContain('01/10/2026');
    expect(items[1]).toContain('Vacía');
    expect(items[1]).toContain('Subtipo: Ciclando');
    expect(items[1]).not.toContain('Más reciente');
  });

  it('says "Este animal tiene una sola palpación" when there is exactly one, and still lists it', async () => {
    const f = setup({ ok: true, rows: [two[1]!] });
    await settled(f);
    expect(el(f).querySelector('[data-testid="drawer-single"]')?.textContent).toContain('Este animal tiene una sola palpación');
    expect(el(f).querySelectorAll('[data-testid="timeline"] li').length).toBe(1);
  });

  it('says "Sin palpaciones registradas" when there are none', async () => {
    const f = setup({ ok: true, rows: [] });
    await settled(f);
    expect(el(f).querySelector('[data-testid="drawer-empty"]')?.textContent).toContain('Sin palpaciones registradas');
    expect(el(f).querySelector('[data-testid="timeline"]')).toBeNull();
  });

  it('shows neither empty message when there are several palpations', async () => {
    const f = setup({ ok: true, rows: two });
    await settled(f);
    expect(el(f).querySelector('[data-testid="drawer-empty"]')).toBeNull();
    expect(el(f).querySelector('[data-testid="drawer-single"]')).toBeNull();
  });

  it('does not count an NR as a palpation: one counted palpation plus one NR is still "una sola palpación"', async () => {
    const nr = eventRow({ livestock_id: 'an-1', health_log_id: 'e3', event_date: '2026-11-07', result: 'VACÍA', ranch_term: 'NR', counts_as_palpation: false, is_clinical_result: false });
    const f = setup({ ok: true, rows: [two[1]!, nr] });
    await settled(f);
    expect(text(f)).toContain('Este animal tiene una sola palpación');
    expect(text(f)).toContain('No examinada (NR)');
    expect(text(f)).toContain('No cuenta como palpada');
  });

  it('shows a ranch term with its badge, an unconfirmed code as typed, and the historical badge', async () => {
    const rows = [
      eventRow({ livestock_id: 'an-1', health_log_id: 'r', event_date: '2026-11-08', result: 'VACÍA', ranch_term: 'RP', is_clinical_result: false }),
      eventRow({ livestock_id: 'an-1', health_log_id: 'u', event_date: '2026-10-08', result: 'VACÍA', mapping_status: 'UNMAPPED', raw_code: 'QUISTE RASTRO' }),
      eventRow({ livestock_id: 'an-1', health_log_id: 'h', event_date: '2023-07-20', result: 'PREÑADA', is_historical_load: true }),
    ];
    const f = setup({ ok: true, rows });
    await settled(f);
    const t = text(f);
    expect(t).toContain('Término del rancho: RP');
    expect(t).toContain('Definido por el rancho');
    expect(t).toContain('código sin confirmar: QUISTE RASTRO');
    expect(t).toContain('histórico (carga 2023)');
  });

  it('shows an error with a generic reason and retries', async () => {
    const f = setup({ ok: false, reason: 'network' });
    await settled(f);
    expect(el(f).querySelector('[role="alert"]')?.textContent).toContain('No hay conexión con el servidor.');
    expect(el(f).querySelector('[data-testid="timeline"]')).toBeNull();
  });

  it('closes with Escape', async () => {
    const f = setup({ ok: true, rows: two });
    await settled(f);
    const spy = vi.fn();
    f.componentInstance.closed.subscribe(spy);
    const ev = key(el(f).querySelector('[role="dialog"]')!, 'Escape');
    expect(spy).toHaveBeenCalledTimes(1);
    expect(ev.defaultPrevented).toBe(true);
  });

  it('closes with the close button and the footer button, and with a click on the backdrop but not inside the panel', async () => {
    const f = setup({ ok: true, rows: two });
    await settled(f);
    const spy = vi.fn();
    f.componentInstance.closed.subscribe(spy);
    (el(f).querySelector('.btn-close') as HTMLButtonElement).click();
    (el(f).querySelector('.modal-footer button') as HTMLButtonElement).click();
    expect(spy).toHaveBeenCalledTimes(2);
    (el(f).querySelector('[role="dialog"]') as HTMLElement).click(); // inside: no close
    expect(spy).toHaveBeenCalledTimes(2);
    (el(f).querySelector('[data-testid="drawer-backdrop"]') as HTMLElement).click(); // backdrop: close
    expect(spy).toHaveBeenCalledTimes(3);
  });

  describe('focus trap', () => {
    it('wraps Tab from the last control to the first', async () => {
      const f = setup({ ok: true, rows: two });
      await settled(f);
      const buttons = [...el(f).querySelectorAll<HTMLElement>('button')];
      const first = buttons[0]!;
      const last = buttons[buttons.length - 1]!;
      last.focus();
      const ev = key(last, 'Tab');
      expect(ev.defaultPrevented).toBe(true);
      expect(document.activeElement).toBe(first);
    });

    it('wraps Shift+Tab from the first control to the last', async () => {
      const f = setup({ ok: true, rows: two });
      await settled(f);
      const buttons = [...el(f).querySelectorAll<HTMLElement>('button')];
      buttons[0]!.focus();
      key(buttons[0]!, 'Tab', true);
      expect(document.activeElement).toBe(buttons[buttons.length - 1]);
    });

    it('brings the focus back inside when it is outside the dialog', async () => {
      const outside = document.createElement('button');
      document.body.appendChild(outside);
      const f = setup({ ok: true, rows: two });
      await settled(f);
      outside.focus();
      key(el(f).querySelector('[data-testid="drawer-backdrop"]')!, 'Tab');
      expect(el(f).contains(document.activeElement)).toBe(true);
      outside.remove();
    });

    it('lets Tab move normally between two controls in the middle', async () => {
      const f = setup({ ok: false, reason: 'network' });
      await settled(f);
      const buttons = [...el(f).querySelectorAll<HTMLElement>('button')];
      expect(buttons.length).toBeGreaterThan(2);
      buttons[1]!.focus();
      const ev = key(buttons[1]!, 'Tab');
      expect(ev.defaultPrevented).toBe(false);
    });
  });

  describe('focus return', () => {
    it('gives the focus back to the element that opened it when it is destroyed', async () => {
      const opener = document.createElement('button');
      document.body.appendChild(opener);
      opener.focus();
      const f = setup({ ok: true, rows: two }, opener);
      await settled(f);
      expect(document.activeElement).not.toBe(opener);
      f.destroy();
      expect(document.activeElement).toBe(opener);
      opener.remove();
    });

    it('falls back to the element that had the focus when it opened', async () => {
      const previous = document.createElement('button');
      document.body.appendChild(previous);
      previous.focus();
      const f = setup({ ok: true, rows: two }, null);
      await settled(f);
      f.destroy();
      expect(document.activeElement).toBe(previous);
      previous.remove();
    });

    it('does not fail when the opener left the page', async () => {
      const opener = document.createElement('button');
      document.body.appendChild(opener);
      const f = setup({ ok: true, rows: two }, opener);
      await settled(f);
      opener.remove();
      expect(() => f.destroy()).not.toThrow();
    });
  });

  it('locks the page scroll while open and releases it on close', async () => {
    const f = setup({ ok: true, rows: two });
    await settled(f);
    expect(document.body.classList.contains('modal-open')).toBe(true);
    f.destroy();
    expect(document.body.classList.contains('modal-open')).toBe(false);
  });
});
