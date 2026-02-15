import { CashRegisterService } from './cash-register.service';
import { TestBed } from '@angular/core/testing';


describe('CashRegisterService', () => {
  let service: CashRegisterService;

  beforeEach(() => {
    TestBed.configureTestingModule({});
    service = TestBed.inject(CashRegisterService);
  });

  it('should be created', () => {
    expect(service).toBeTruthy();
  });
});
