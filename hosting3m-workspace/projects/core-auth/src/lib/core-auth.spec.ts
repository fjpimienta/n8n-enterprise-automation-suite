import { ComponentFixture, TestBed } from '@angular/core/testing';

import { CoreAuth } from './core-auth';

describe('CoreAuth', () => {
  let component: CoreAuth;
  let fixture: ComponentFixture<CoreAuth>;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [CoreAuth]
    })
    .compileComponents();

    fixture = TestBed.createComponent(CoreAuth);
    component = fixture.componentInstance;
    await fixture.whenStable();
  });

  it('should create', () => {
    expect(component).toBeTruthy();
  });
});
