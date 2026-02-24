import { ComponentFixture, TestBed } from '@angular/core/testing';

import { CanvasEngineComponent } from './canvas-engine.component';

describe('CanvasEngineComponent', () => {
  let component: CanvasEngineComponent;
  let fixture: ComponentFixture<CanvasEngineComponent>;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [CanvasEngineComponent]
    })
    .compileComponents();

    fixture = TestBed.createComponent(CanvasEngineComponent);
    component = fixture.componentInstance;
    await fixture.whenStable();
  });

  it('should create', () => {
    expect(component).toBeTruthy();
  });
});
