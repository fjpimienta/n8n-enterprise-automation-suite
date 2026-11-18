import { ComponentFixture, TestBed } from '@angular/core/testing';
import { describe, expect, it, vi } from 'vitest';
import { PalpationStateComponent, PalpationStateKind } from './palpation-state.component';

function render(kind: PalpationStateKind, extra: { reason?: string | null; count?: number } = {}): ComponentFixture<PalpationStateComponent> {
  const fixture = TestBed.createComponent(PalpationStateComponent);
  fixture.componentRef.setInput('kind', kind);
  if (extra.reason !== undefined) fixture.componentRef.setInput('reason', extra.reason);
  if (extra.count !== undefined) fixture.componentRef.setInput('count', extra.count);
  fixture.detectChanges();
  return fixture;
}

const text = (f: ComponentFixture<unknown>) => (f.nativeElement as HTMLElement).textContent?.replace(/\s+/g, ' ').trim() ?? '';
const q = (f: ComponentFixture<unknown>, sel: string) => (f.nativeElement as HTMLElement).querySelector(sel);

describe('PalpationStateComponent', () => {
  it('shows the loading state as a polite, busy status', () => {
    const f = render('cargando');
    expect(text(f)).toContain('Cargando palpaciones');
    expect(q(f, '[role="status"]')?.getAttribute('aria-busy')).toBe('true');
  });

  it('shows the empty state', () => {
    expect(text(render('vacio'))).toContain('No hay palpaciones registradas');
  });

  it('shows an error with a generic Spanish reason and a retry button, and no numbers', () => {
    const f = render('error', { reason: 'empty-body' });
    expect(text(f)).toContain('No se pudieron cargar las palpaciones');
    expect(text(f)).toContain('El servidor respondió sin datos.');
    expect(q(f, '[role="alert"]')).not.toBeNull();
  });

  it('emits retry when the retry button is pressed', () => {
    const f = render('error', { reason: 'network' });
    const spy = vi.fn();
    f.componentInstance.retry.subscribe(spy);
    (q(f, 'button') as HTMLButtonElement).click();
    expect(spy).toHaveBeenCalledTimes(1);
  });

  it('shows "sin permiso" as an alert', () => {
    const f = render('sin-permiso');
    expect(text(f)).toContain('Tu rol en esta empresa no permite ver el reporte de palpaciones');
    expect(q(f, '[role="alert"]')).not.toBeNull();
  });

  it('shows "sin tenant"', () => {
    expect(text(render('sin-tenant'))).toContain('Selecciona una empresa');
  });

  it('shows "sin campaña" with a button that emits showAll', () => {
    const f = render('sin-campana');
    expect(text(f)).toContain('Aún no hay palpaciones de una campaña reciente');
    const spy = vi.fn();
    f.componentInstance.showAll.subscribe(spy);
    (q(f, 'button') as HTMLButtonElement).click();
    expect(spy).toHaveBeenCalledTimes(1);
    expect(text(f)).toContain('Ver todo el historial');
  });

  it('shows the truncation banner with the number of rows loaded', () => {
    const f = render('truncado', { count: 15000 });
    expect(text(f)).toContain('Reporte incompleto');
    expect(text(f)).toContain('15000 filas');
    expect(q(f, '[role="alert"]')).not.toBeNull();
  });

  it('shows the unrecognised-values warning, singular and plural', () => {
    expect(text(render('no-reconocidos', { count: 1 }))).toContain('1 registro tiene un resultado o un término que la aplicación no reconoce');
    const many = text(render('no-reconocidos', { count: 3 }));
    expect(many).toContain('3 registros tienen');
    expect(many).toContain('no cuentan en los porcentajes');
  });
});
