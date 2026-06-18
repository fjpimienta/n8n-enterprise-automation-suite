import { ComponentFixture, TestBed } from '@angular/core/testing';

import { ReproductiveDashboard } from './reproductive-dashboard';

describe('ReproductiveDashboard', () => {
  let component: ReproductiveDashboard;
  let fixture: ComponentFixture<ReproductiveDashboard>;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [ReproductiveDashboard]
    })
    .compileComponents();

    fixture = TestBed.createComponent(ReproductiveDashboard);
    component = fixture.componentInstance;
    await fixture.whenStable();
  });

  it('should create', () => {
    expect(component).toBeTruthy();
  });
});
