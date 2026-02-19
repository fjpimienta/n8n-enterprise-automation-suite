import { AssetFormModalComponent } from './asset-form-modal.component';
import { ComponentFixture, TestBed } from '@angular/core/testing';


describe('AssetFormModal', () => {
  let component: AssetFormModalComponent;
  let fixture: ComponentFixture<AssetFormModalComponent>;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [AssetFormModalComponent]
    })
    .compileComponents();

    fixture = TestBed.createComponent(AssetFormModalComponent);
    component = fixture.componentInstance;
    fixture.componentRef.setInput('isOpen', false);
    fixture.detectChanges();
    await fixture.whenStable();
  });

  it('should create', () => {
    expect(component).toBeTruthy();
  });
});
