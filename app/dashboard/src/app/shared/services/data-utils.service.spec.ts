import { TestBed } from '@angular/core/testing';

import { DataUtilsService } from './data-utils.service';

describe('DataUtilsService', () => {
  let service: DataUtilsService;

  beforeEach(() => {
    TestBed.configureTestingModule({});
    service = TestBed.inject(DataUtilsService);
  });

  it('should be created', () => {
    expect(service).toBeTruthy();
  });
});
