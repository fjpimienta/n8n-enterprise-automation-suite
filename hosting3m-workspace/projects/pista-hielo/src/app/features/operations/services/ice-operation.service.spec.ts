import { TestBed } from '@angular/core/testing';
import { IceOperationsService } from '@features/operations/services/ice-operation.service';

describe('IceOperation', () => {
  let service: IceOperationsService;

  beforeEach(() => {
    TestBed.configureTestingModule({});
    service = TestBed.inject(IceOperationsService);
  });

  it('should be created', () => {
    expect(service).toBeTruthy();
  });
});
