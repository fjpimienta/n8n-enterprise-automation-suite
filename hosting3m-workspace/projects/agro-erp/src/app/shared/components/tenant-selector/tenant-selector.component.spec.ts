import { ComponentFixture, TestBed } from '@angular/core/testing';

import { TenantSelectorComponent } from './tenant-selector.component';

describe('TenantSelectorComponent', () => {
  let component: TenantSelectorComponent;
  let fixture: ComponentFixture<TenantSelectorComponent>;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [TenantSelectorComponent]
    })
    .compileComponents();

    fixture = TestBed.createComponent(TenantSelectorComponent);
    component = fixture.componentInstance;
    await fixture.whenStable();
  });

  it('should create', () => {
    expect(component).toBeTruthy();
  });
});
