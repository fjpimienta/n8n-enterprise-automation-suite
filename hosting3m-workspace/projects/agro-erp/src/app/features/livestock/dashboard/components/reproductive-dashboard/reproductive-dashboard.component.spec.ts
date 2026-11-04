import { ComponentFixture, TestBed } from '@angular/core/testing';

import { ReproductiveDashboardComponent } from './reproductive-dashboard.component';

describe('ReproductiveDashboardComponent', () => {
  let component: ReproductiveDashboardComponent;
  let fixture: ComponentFixture<ReproductiveDashboardComponent>;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [ReproductiveDashboardComponent]
    })
    .compileComponents();

    fixture = TestBed.createComponent(ReproductiveDashboardComponent);
    component = fixture.componentInstance;
    await fixture.whenStable();
  });

  it('should create', () => {
    expect(component).toBeTruthy();
  });
});
