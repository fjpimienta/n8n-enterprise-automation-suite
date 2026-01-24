import { ComponentFixture, TestBed } from '@angular/core/testing';

import { EntryForm } from './entry-form';

describe('EntryForm', () => {
  let component: EntryForm;
  let fixture: ComponentFixture<EntryForm>;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [EntryForm]
    })
    .compileComponents();

    fixture = TestBed.createComponent(EntryForm);
    component = fixture.componentInstance;
    await fixture.whenStable();
  });

  it('should create', () => {
    expect(component).toBeTruthy();
  });
});
