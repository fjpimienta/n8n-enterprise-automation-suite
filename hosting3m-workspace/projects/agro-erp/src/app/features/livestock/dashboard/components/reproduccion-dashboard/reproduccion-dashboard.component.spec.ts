import { ComponentFixture, TestBed } from '@angular/core/testing';

import { ReproduccionDashboardComponent } from './reproduccion-dashboard.component';

describe('ReproduccionDashboardComponent', () => {
  let component: ReproduccionDashboardComponent;
  let fixture: ComponentFixture<ReproduccionDashboardComponent>;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [ReproduccionDashboardComponent]
    })
      .compileComponents();

    fixture = TestBed.createComponent(ReproduccionDashboardComponent);
    component = fixture.componentInstance;
    await fixture.whenStable();
  });

  it('should create', () => {
    expect(component).toBeTruthy();
  });
});
