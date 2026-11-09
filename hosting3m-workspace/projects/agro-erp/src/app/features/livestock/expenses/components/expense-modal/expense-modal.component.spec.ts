import { ComponentFixture, TestBed } from '@angular/core/testing';

import { ExpenseModalComponent } from './expense-modal.component';

describe('ExpenseModalComponent', () => {
  let component: ExpenseModalComponent;
  let fixture: ComponentFixture<ExpenseModalComponent>;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [ExpenseModalComponent]
    })
    .compileComponents();

    fixture = TestBed.createComponent(ExpenseModalComponent);
    component = fixture.componentInstance;
    await fixture.whenStable();
  });

  it('should create', () => {
    expect(component).toBeTruthy();
  });

  describe('layout', () => {
    const render = () => {
      fixture.detectChanges();
      return fixture.nativeElement as HTMLElement;
    };
    const save = (el: HTMLElement) => el.querySelector('button[type=submit]') as HTMLButtonElement;

    it('disables the primary button until the form is valid and shows the amount in its label', () => {
      const el = render();
      expect(save(el).disabled).toBe(true);
      component.pickCategory('MEDICINA');
      component.expenseForm.controls.amount.setValue(1250.5);
      fixture.detectChanges();
      expect(save(el).disabled).toBe(false);
      expect(save(el).textContent).toContain('Guardar gasto · $1,250.50');
    });

    it('offers the four categories as chips and selects one into the form', () => {
      const el = render();
      const chips = Array.from(el.querySelectorAll('exp-category-chips button')) as HTMLButtonElement[];
      expect(chips.map(c => c.textContent?.trim())).toEqual(['Alimentación', 'Medicina y sanidad', 'Suplementos', 'Manejo y fletes']);
      chips[2].click();
      fixture.detectChanges();
      expect(component.expenseForm.value.category).toBe('SUPLEMENTOS');
      expect(chips[2].getAttribute('aria-pressed')).toBe('true');
    });

    it('keeps the optional fields under a collapsed "Más detalles" section and the form defaults', () => {
      const el = render();
      const details = el.querySelector('details') as HTMLDetailsElement;
      expect(details.open).toBe(false);
      expect(details.textContent).toContain('Más detalles (opcional)');
      expect(details.querySelector('#ls-exp-desc')).not.toBeNull();
      expect(details.querySelector('#ls-exp-qty')).not.toBeNull();
      expect(component.expenseForm.value.unit_measure).toBe('KG');
      expect(component.expenseForm.controls.amount.hasError('min')).toBe(false);
      component.expenseForm.controls.amount.setValue(0);
      expect(component.expenseForm.controls.amount.hasError('min')).toBe(true);
    });
  });
});
