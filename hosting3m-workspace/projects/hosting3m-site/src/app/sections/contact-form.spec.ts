import { TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { of } from 'rxjs';
import { ContactService } from '../core/contact';
import { ContactForm } from './contact-form';

describe('ContactForm after a successful submit', () => {
  function setup(mensaje: string) {
    const send = vi.fn(() => of(mensaje));
    TestBed.configureTestingModule({
      providers: [provideRouter([]), { provide: ContactService, useValue: { send } }],
    });
    const fixture = TestBed.createComponent(ContactForm);
    fixture.componentInstance.token.set('tok');
    fixture.componentInstance.form.setValue({
      names: 'Ana', middlename: '', lastname: 'López', phone: '', email: 'ana@example.com',
      service: '', message: 'Hola', privacy: true, empresa: '',
    });
    return { fixture, send };
  }

  it('shows the server message and no validation errors', async () => {
    const { fixture, send } = setup('Mensaje del servidor');
    await fixture.componentInstance.submit();
    fixture.detectChanges();
    const el: HTMLElement = fixture.nativeElement;
    expect(send).toHaveBeenCalledTimes(1);
    expect(el.querySelectorAll('.field-error')).toHaveLength(0);
    const status = el.querySelector('#form-status');
    expect(status?.getAttribute('role')).toBe('status');
    expect(status?.textContent).toContain('Mensaje del servidor');
    expect(fixture.componentInstance.form.touched).toBe(false);
    expect(fixture.componentInstance.form.dirty).toBe(false);
  });

  it('falls back to the default message', async () => {
    const { fixture } = setup('');
    await fixture.componentInstance.submit();
    fixture.detectChanges();
    expect(fixture.nativeElement.querySelector('#form-status').textContent).toContain('¡Gracias! Hemos recibido tu mensaje.');
  });
});
