import { TestBed } from '@angular/core/testing';

import { ThreeState } from './three-state';

describe('ThreeState', () => {
  let service: ThreeState;

  beforeEach(() => {
    TestBed.configureTestingModule({});
    service = TestBed.inject(ThreeState);
  });

  it('should be created', () => {
    expect(service).toBeTruthy();
  });
});
