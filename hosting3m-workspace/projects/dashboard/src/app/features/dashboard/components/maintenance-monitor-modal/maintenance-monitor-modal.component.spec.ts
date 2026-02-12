import { ComponentFixture, TestBed } from '@angular/core/testing';

import { MaintenanceMonitorModal } from './maintenance-monitor-modal';

describe('MaintenanceMonitorModal', () => {
  let component: MaintenanceMonitorModal;
  let fixture: ComponentFixture<MaintenanceMonitorModal>;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [MaintenanceMonitorModal]
    })
    .compileComponents();

    fixture = TestBed.createComponent(MaintenanceMonitorModal);
    component = fixture.componentInstance;
    await fixture.whenStable();
  });

  it('should create', () => {
    expect(component).toBeTruthy();
  });
});
