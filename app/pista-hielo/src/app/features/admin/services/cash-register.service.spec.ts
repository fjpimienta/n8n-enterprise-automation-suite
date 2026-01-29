import { CashRegisterService } from './cash-register.service';
import { TestBed } from '@angular/core/testing';


describe('CashRegister', () => {
  let service: CashRegisterService;

  beforeEach(() => {
    TestBed.configureTestingModule({});
    service = TestBed.inject(CashRegister);
  });

  it('should be created', () => {
    expect(service).toBeTruthy();
  });
});
