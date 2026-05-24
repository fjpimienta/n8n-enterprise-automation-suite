import { ComponentFixture, TestBed } from '@angular/core/testing';

import { ExpenseModal } from './expense-modal';

describe('ExpenseModal', () => {
  let component: ExpenseModal;
  let fixture: ComponentFixture<ExpenseModal>;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [ExpenseModal]
    })
    .compileComponents();

    fixture = TestBed.createComponent(ExpenseModal);
    component = fixture.componentInstance;
    await fixture.whenStable();
  });

  it('should create', () => {
    expect(component).toBeTruthy();
  });
});
