import { TestBed } from '@angular/core/testing';

import { IceOperation } from './ice-operation';

describe('IceOperation', () => {
  let service: IceOperation;

  beforeEach(() => {
    TestBed.configureTestingModule({});
    service = TestBed.inject(IceOperation);
  });

  it('should be created', () => {
    expect(service).toBeTruthy();
  });
});
