import { Component, signal } from '@angular/core';
import { TestBed } from '@angular/core/testing';
import { describe, expect, it } from 'vitest';
import { CategoryChipsComponent, DetailPanelComponent, KpiCardComponent, PeriodChipsComponent, ShareBarListComponent, TrendBarsComponent } from './index';
import { deltaPercent, formatDelta, formatPercent, sharePercent } from './expenses-ui.util';

function render<T>(type: new () => T, inputs: Record<string, unknown>) {
  const fixture = TestBed.createComponent(type);
  for (const [k, v] of Object.entries(inputs)) fixture.componentRef.setInput(k, v);
  fixture.detectChanges();
  return { fixture, el: fixture.nativeElement as HTMLElement };
}

describe('expenses-ui util', () => {
  it('derives share and delta', () => {
    expect(sharePercent(1, 4)).toBe(25);
    expect(formatPercent(12.34)).toBe('12.3%');
    expect(formatDelta(deltaPercent(110, 100))).toBe('+10%');
  });
});

describe('exp-kpi-card', () => {
  it('shows label, value, hint and the delta with an arrow', () => {
    const { el } = render(KpiCardComponent, { label: 'Total', value: '$1.00', hint: '3 gastos', deltaText: '+10%', tone: 'up' });
    expect(el.textContent).toContain('Total');
    expect(el.textContent).toContain('$1.00');
    expect(el.textContent).toContain('3 gastos');
    expect(el.querySelector('.kpi-delta')?.textContent).toContain('▲ +10%');
  });
  it('hides the delta when empty', () => {
    const { el } = render(KpiCardComponent, { label: 'Total', value: '$1.00' });
    expect(el.querySelector('.kpi-delta')).toBeNull();
  });
});

describe('exp-period-chips', () => {
  it('marks the active chip with aria-pressed and emits on click', () => {
    const { fixture, el } = render(PeriodChipsComponent, { options: [{ value: 'A', label: 'Uno' }, { value: 'B', label: 'Dos' }], value: 'B' });
    const buttons = Array.from(el.querySelectorAll('button'));
    expect(buttons.map(b => b.getAttribute('aria-pressed'))).toEqual(['false', 'true']);
    const emitted: string[] = [];
    fixture.componentInstance.valueChange.subscribe(v => emitted.push(v));
    buttons[0].click();
    expect(emitted).toEqual(['A']);
  });
});

describe('exp-category-chips', () => {
  it('adds an "all" chip that emits an empty value', () => {
    const { fixture, el } = render(CategoryChipsComponent, { options: [{ value: 'c1', label: 'Fert' }], value: '', allowAll: true });
    const buttons = Array.from(el.querySelectorAll('button'));
    expect(buttons.map(b => b.textContent?.trim())).toEqual(['Todas', 'Fert']);
    expect(buttons[0].getAttribute('aria-pressed')).toBe('true');
    const emitted: string[] = [];
    fixture.componentInstance.valueChange.subscribe(v => emitted.push(v));
    buttons[1].click();
    expect(emitted).toEqual(['c1']);
  });
  it('has no "all" chip by default', () => {
    const { el } = render(CategoryChipsComponent, { options: [{ value: 'c1', label: 'Fert' }], value: 'c1' });
    expect(el.querySelectorAll('button').length).toBe(1);
  });
});

describe('exp-share-bar-list', () => {
  it('renders label, amount, percent and a bar width', () => {
    const { el } = render(ShareBarListComponent, { items: [
      { key: 'a', label: 'A', amount: 75, amountText: '$75' }, { key: 'b', label: 'B', amount: 25, amountText: '$25' }] });
    expect(el.textContent).toContain('75%');
    expect(el.textContent).toContain('$25');
    expect((el.querySelector('.fill') as HTMLElement).style.width).toBe('75%');
  });
  it('shows the empty text', () => {
    const { el } = render(ShareBarListComponent, { items: [], emptyText: 'Nada' });
    expect(el.textContent).toContain('Nada');
  });
});

describe('exp-trend-bars', () => {
  const bars = [
    { key: '1', label: 'ene', value: 10, valueText: '$10', heightPct: 100, inProgress: false },
    { key: '2', label: 'feb', value: 5, valueText: '$5', heightPct: 50, inProgress: true }];
  it('gives every bar a text value and tags the one in progress', () => {
    const { el } = render(TrendBarsComponent, { bars });
    expect(el.querySelectorAll('.bar').length).toBe(2);
    expect(el.querySelector('.bar.live')).not.toBeNull();
    expect(el.textContent).toContain('$10');
    expect(el.textContent).toContain('feb (en curso)');
  });
  it('shows the empty state', () => {
    const { el } = render(TrendBarsComponent, { bars: [], emptyText: 'Vacío' });
    expect(el.textContent).toContain('Vacío');
  });
});

@Component({
  standalone: true, imports: [DetailPanelComponent],
  template: `<exp-detail-panel heading="Detalle" (closed)="closes.set(closes() + 1)"><p>cuerpo</p><button panelFooter>Acción</button></exp-detail-panel>`,
})
class HostComponent { closes = signal(0); }

describe('exp-detail-panel', () => {
  it('projects body and footer, and closes through an labelled button', () => {
    const fixture = TestBed.createComponent(HostComponent);
    fixture.detectChanges();
    const el = fixture.nativeElement as HTMLElement;
    expect(el.textContent).toContain('cuerpo');
    expect(el.querySelector('footer button')?.textContent).toContain('Acción');
    const close = el.querySelector('button[aria-label="Cerrar detalle"]') as HTMLButtonElement;
    close.click();
    expect(fixture.componentInstance.closes()).toBe(1);
  });
});
