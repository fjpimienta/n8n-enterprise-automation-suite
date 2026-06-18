import { AssetService } from './asset.service';
import { TestBed } from '@angular/core/testing';


describe('Asset', () => {
  let service: AssetService;

  beforeEach(() => {
    TestBed.configureTestingModule({});
    service = TestBed.inject(AssetService);
  });

  it('should be created', () => {
    expect(service).toBeTruthy();
  });
});
