import { ComponentFixture, TestBed } from '@angular/core/testing';

import { DailyReport } from './daily-report';

describe('DailyReport', () => {
  let component: DailyReport;
  let fixture: ComponentFixture<DailyReport>;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [DailyReport]
    })
    .compileComponents();

    fixture = TestBed.createComponent(DailyReport);
    component = fixture.componentInstance;
    await fixture.whenStable();
  });

  it('should create', () => {
    expect(component).toBeTruthy();
  });
});
