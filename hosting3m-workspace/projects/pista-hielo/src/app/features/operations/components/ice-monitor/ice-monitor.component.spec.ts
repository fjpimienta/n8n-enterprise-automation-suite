import { ComponentFixture, TestBed } from '@angular/core/testing';

import { IceMonitorComponent } from './ice-monitor.component';
import { LucideAngularModule, RefreshCw } from 'lucide-angular';

describe('IceMonitorComponent', () => {
  let component: IceMonitorComponent;
  let fixture: ComponentFixture<IceMonitorComponent>;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [IceMonitorComponent,
        LucideAngularModule.pick({ RefreshCw })]
    })
      .compileComponents();

    fixture = TestBed.createComponent(IceMonitorComponent);
    component = fixture.componentInstance;
    await fixture.whenStable();
  });

  it('should create', () => {
    expect(component).toBeTruthy();
  });
});
