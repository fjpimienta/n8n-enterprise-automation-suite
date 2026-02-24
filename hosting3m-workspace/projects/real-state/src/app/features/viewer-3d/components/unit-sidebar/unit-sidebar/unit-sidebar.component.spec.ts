import { ComponentFixture, TestBed } from '@angular/core/testing';

import { UnitSidebar } from './unit-sidebar';

describe('UnitSidebar', () => {
  let component: UnitSidebar;
  let fixture: ComponentFixture<UnitSidebar>;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [UnitSidebar]
    })
    .compileComponents();

    fixture = TestBed.createComponent(UnitSidebar);
    component = fixture.componentInstance;
    await fixture.whenStable();
  });

  it('should create', () => {
    expect(component).toBeTruthy();
  });
});
