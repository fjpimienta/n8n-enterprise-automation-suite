import { ComponentFixture, TestBed } from '@angular/core/testing';
import { describe, expect, it } from 'vitest';
import { eventRow } from '../../testing/palpation.fixtures';
import { PeriodKpis, periodKpis } from '../../utils/palpation-metrics';
import { PalpationKpiCardsComponent } from './palpation-kpi-cards.component';

const PERIOD = { from: '2026-09-11', to: '2026-11-10' };
const events = [
  eventRow({ livestock_id: 'A1', health_log_id: 'e1', event_date: '2026-11-10', result: 'VACÍA', repro_condition: 'ESTATICA', mapping_status: 'EXPLICIT' }),
  eventRow({ livestock_id: 'A2', health_log_id: 'e2', event_date: '2026-09-20', result: 'PREÑADA', gestation_days: 90 }),
  eventRow({ livestock_id: 'A5', health_log_id: 'e5', event_date: '2026-10-05', result: 'VACÍA', ranch_term: 'RP', is_clinical_result: false }),
  eventRow({ livestock_id: 'A6', health_log_id: 'e6', event_date: '2026-10-20', result: 'VACÍA', mapping_status: 'UNMAPPED', raw_code: 'DF15' }),
  eventRow({ livestock_id: 'A7', health_log_id: 'e7', event_date: '2026-10-22', result: null, is_clinical_result: false }),
];

function render(kpis: PeriodKpis): ComponentFixture<PalpationKpiCardsComponent> {
  const fixture = TestBed.createComponent(PalpationKpiCardsComponent);
  fixture.componentRef.setInput('kpis', kpis);
  fixture.componentRef.setInput('periodLabel', 'campaña reciente');
  fixture.detectChanges();
  return fixture;
}
const el = (f: ComponentFixture<unknown>) => f.nativeElement as HTMLElement;
const tid = (f: ComponentFixture<unknown>, id: string) => el(f).querySelector(`[data-testid="${id}"]`)?.textContent?.trim();

describe('PalpationKpiCardsComponent', () => {
  it('shows each figure with its absolute number and its denominator', () => {
    const f = render(periodKpis(events, PERIOD));
    expect(tid(f, 'kpi-palpated')).toBe('5');
    expect(tid(f, 'kpi-pregnant')).toBe('1');
    expect(tid(f, 'kpi-empty')).toBe('2');
    expect(tid(f, 'kpi-pregnant-pct')).toBe('33,3 %');
    expect(tid(f, 'kpi-empty-pct')).toBe('66,7 %');
    const text = el(f).textContent?.replace(/\s+/g, ' ') ?? '';
    expect(text).toContain('de 3 con resultado clínico');
    expect(text).toContain('de 5 animales palpados');
  });

  it('shows the unconfirmed codes, the last date and the sub-types of the empty animals', () => {
    const f = render(periodKpis(events, PERIOD));
    expect(tid(f, 'kpi-unconfirmed')).toBe('1');
    expect(tid(f, 'kpi-last')).toBe('10/11/2026');
    const text = el(f).textContent?.replace(/\s+/g, ' ') ?? '';
    expect(text).toContain('Estática (UNE): 1');
    expect(text).toContain('Código sin confirmar: 1');
  });

  it('keeps ranch terms and animals without a result outside the percentages, with the ranch badge', () => {
    const f = render(periodKpis(events, PERIOD));
    const text = el(f).textContent?.replace(/\s+/g, ' ') ?? '';
    expect(text).toContain('Definido por el rancho');
    expect(tid(f, 'kpi-ranch')).toBe('1');
    expect(tid(f, 'kpi-no-result')).toBe('1');
    expect(text).toContain('RP 1');
    expect(text).toContain('NR) no cuenta como palpado');
  });

  it('shows an em dash instead of 0 % when there is no clinical result', () => {
    const only = [eventRow({ livestock_id: 'R', health_log_id: 'r1', event_date: '2026-11-02', result: 'VACÍA', ranch_term: 'NO APTO', is_clinical_result: false })];
    const f = render(periodKpis(only, PERIOD));
    expect(tid(f, 'kpi-pregnant-pct')).toBe('—');
    expect(tid(f, 'kpi-empty-pct')).toBe('—');
  });

  it('shows the uninterpreted count only when there is one', () => {
    expect(tid(render(periodKpis(events, PERIOD)), 'kpi-uninterpreted')).toBeUndefined();
    const withUnknown = [...events, eventRow({ livestock_id: 'U', health_log_id: 'u', event_date: '2026-11-01', result: null, uninterpreted: true, is_clinical_result: false })];
    expect(tid(render(periodKpis(withUnknown, PERIOD)), 'kpi-uninterpreted')).toBe('1');
  });

  it('shows an alert and no figures when the counts do not add up', () => {
    const broken: PeriodKpis = { ...periodKpis(events, PERIOD), identityHolds: false };
    const f = render(broken);
    expect(el(f).querySelector('[role="alert"]')?.textContent).toContain('Las cifras no cuadran');
    expect(tid(f, 'kpi-palpated')).toBeUndefined();
  });
});
