import { ComponentFixture, TestBed } from '@angular/core/testing';

import { InventoryManagerComponent } from './inventory-manager.component';

describe('InventoryManagerComponent', () => {
  let component: InventoryManagerComponent;
  let fixture: ComponentFixture<InventoryManagerComponent>;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [InventoryManagerComponent]
    })
    .compileComponents();

    fixture = TestBed.createComponent(InventoryManagerComponent);
    component = fixture.componentInstance;
    await fixture.whenStable();
  });

  it('should create', () => {
    expect(component).toBeTruthy();
  });
});
