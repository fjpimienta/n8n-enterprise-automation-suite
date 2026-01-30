import { ClientListComponent } from './client-list.component';
import { ComponentFixture, TestBed } from '@angular/core/testing';


describe('ClientList', () => {
  let component: ClientListComponent;
  let fixture: ComponentFixture<ClientListComponent>;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [ClientListComponent]
    })
    .compileComponents();

    fixture = TestBed.createComponent(ClientListComponent);
    component = fixture.componentInstance;
    await fixture.whenStable();
  });

  it('should create', () => {
    expect(component).toBeTruthy();
  });
});
