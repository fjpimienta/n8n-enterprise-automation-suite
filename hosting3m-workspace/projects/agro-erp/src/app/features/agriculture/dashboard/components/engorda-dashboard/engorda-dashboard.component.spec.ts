import { ComponentFixture, TestBed } from '@angular/core/testing';

import { EngordaDashboardComponent } from './engorda-dashboard.component';

describe('EngordaDashboardComponent', () => {
  let component: EngordaDashboardComponent;
  let fixture: ComponentFixture<EngordaDashboardComponent>;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [EngordaDashboardComponent]
    })
      .compileComponents();

    fixture = TestBed.createComponent(EngordaDashboardComponent);
    component = fixture.componentInstance;
    await fixture.whenStable();
  });

  it('should create', () => {
    expect(component).toBeTruthy();
  });
});
