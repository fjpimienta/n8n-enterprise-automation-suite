import { ComponentFixture, TestBed } from '@angular/core/testing';

import { InventoryManager } from './inventory-manager';

describe('InventoryManager', () => {
  let component: InventoryManager;
  let fixture: ComponentFixture<InventoryManager>;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [InventoryManager]
    })
    .compileComponents();

    fixture = TestBed.createComponent(InventoryManager);
    component = fixture.componentInstance;
    await fixture.whenStable();
  });

  it('should create', () => {
    expect(component).toBeTruthy();
  });
});
