import { ComponentFixture, TestBed } from '@angular/core/testing';

import { MaintenanceMonitorModalComponent } from './maintenance-monitor-modal.component';

describe('MaintenanceMonitorModalComponent', () => {
  let component: MaintenanceMonitorModalComponent;
  let fixture: ComponentFixture<MaintenanceMonitorModalComponent>;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [MaintenanceMonitorModalComponent]
    })
    .compileComponents();

    fixture = TestBed.createComponent(MaintenanceMonitorModalComponent);
    component = fixture.componentInstance;
    await fixture.whenStable();
  });

  it('should create', () => {
    expect(component).toBeTruthy();
  });
});
