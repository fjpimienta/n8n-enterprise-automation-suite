import { ComponentFixture, TestBed } from '@angular/core/testing';

import { ClosureManager } from './closure-manager';

describe('ClosureManager', () => {
  let component: ClosureManager;
  let fixture: ComponentFixture<ClosureManager>;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [ClosureManager]
    })
    .compileComponents();

    fixture = TestBed.createComponent(ClosureManager);
    component = fixture.componentInstance;
    await fixture.whenStable();
  });

  it('should create', () => {
    expect(component).toBeTruthy();
  });
});
