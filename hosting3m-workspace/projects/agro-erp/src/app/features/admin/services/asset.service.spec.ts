import { AuthService } from 'core-auth';
import { AssetService } from './asset.service';
import { TestBed } from '@angular/core/testing';


describe('Asset', () => {
  let service: AssetService;

  beforeEach(() => {
    TestBed.configureTestingModule({
      providers: [{ provide: AuthService, useValue: { getSessionState: () => 'valid' } }],
    });
    service = TestBed.inject(AssetService);
  });

  it('should be created', () => {
    expect(service).toBeTruthy();
  });
});
