import { ComponentFixture, TestBed } from '@angular/core/testing';

import { ExpenseFormModal } from './expense-form-modal.component';

describe('ExpenseFormModal', () => {
  let component: ExpenseFormModal;
  let fixture: ComponentFixture<ExpenseFormModal>;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [ExpenseFormModal]
    })
    .compileComponents();

    fixture = TestBed.createComponent(ExpenseFormModal);
    component = fixture.componentInstance;
    await fixture.whenStable();
  });

  it('should create', () => {
    expect(component).toBeTruthy();
  });
});
