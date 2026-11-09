import { TestBed } from '@angular/core/testing';
import { describe, expect, it } from 'vitest';
import type { ExpenseCategory } from '@core/models/agri-expense.model';
import { emptyExpenseInput } from '../utils/expense.util';
import { ExpenseFormModalComponent } from './expense-form-modal.component';

const category = (id: string, name: string): ExpenseCategory => ({ id, idCompany: 10, code: name.toUpperCase(), name, sortOrder: 1, isActive: true });

function setup() {
  const fixture = TestBed.createComponent(ExpenseFormModalComponent);
  fixture.componentRef.setInput('isOpen', true);
  fixture.componentRef.setInput('today', '2026-10-20');
  fixture.componentRef.setInput('categories', [category('c1', 'Fertilizantes'), category('c2', 'Combustible')]);
  fixture.componentRef.setInput('data', emptyExpenseInput('', '2026-10-20'));
  fixture.detectChanges();
  const el = fixture.nativeElement as HTMLElement;
  const save = () => Array.from(el.querySelectorAll('.modal-footer button')).find(b => b.classList.contains('btn-save')) as HTMLButtonElement;
  return { fixture, el, save, cmp: fixture.componentInstance };
}

describe('ExpenseFormModalComponent', () => {
  it('disables the primary button until amount and category are valid, then shows the amount', () => {
    const { fixture, save, cmp } = setup();
    expect(save().disabled).toBe(true);
    cmp.set('categoryId', 'c1');
    fixture.detectChanges();
    expect(save().disabled).toBe(true);
    cmp.set('amount', '1,250.50');
    fixture.detectChanges();
    expect(save().disabled).toBe(false);
    expect(save().textContent).toContain('$1,250.50');
  });

  it('defaults the date to "Hoy" and the shortcuts set the date', () => {
    const { fixture, el, cmp } = setup();
    const pressed = () => Array.from(el.querySelectorAll('.seg button')).map(b => b.getAttribute('aria-pressed'));
    expect(pressed()).toEqual(['true', 'false', 'false']);
    cmp.pickYesterday();
    fixture.detectChanges();
    expect(cmp.data().expenseDate).toBe('2026-10-19');
    expect(pressed()).toEqual(['false', 'true', 'false']);
    cmp.forceOther.set(true);
    fixture.detectChanges();
    expect(pressed()).toEqual(['false', 'false', 'true']);
    expect(el.querySelector('input[type=date]')).not.toBeNull();
  });

  it('keeps the optional fields under a collapsed "Más detalles" section', () => {
    const { el } = setup();
    const details = el.querySelector('details') as HTMLDetailsElement;
    expect(details.open).toBe(false);
    expect(details.querySelector('summary')?.textContent).toContain('Más detalles (opcional)');
    expect(details.querySelector('#exp-form-supplier')).not.toBeNull();
  });
});
