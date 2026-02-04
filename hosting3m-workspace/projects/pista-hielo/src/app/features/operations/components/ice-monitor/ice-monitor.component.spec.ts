import { ComponentFixture, TestBed } from '@angular/core/testing';

import { IceMonitor } from './ice-monitor.component';

describe('IceMonitor', () => {
  let component: IceMonitor;
  let fixture: ComponentFixture<IceMonitor>;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [IceMonitor]
    })
    .compileComponents();

    fixture = TestBed.createComponent(IceMonitor);
    component = fixture.componentInstance;
    await fixture.whenStable();
  });

  it('should create', () => {
    expect(component).toBeTruthy();
  });
});
