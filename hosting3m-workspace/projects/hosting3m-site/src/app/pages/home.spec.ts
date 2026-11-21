import { TestBed } from '@angular/core/testing';
import { provideHttpClient } from '@angular/common/http';
import { provideHttpClientTesting } from '@angular/common/http/testing';
import { provideRouter } from '@angular/router';
import { PlansService } from '../core/plans';
import { Home } from './home';

describe('Home page (redesign D)', () => {
  function render() {
    TestBed.configureTestingModule({ providers: [provideRouter([]), provideHttpClient(), provideHttpClientTesting()] });
    TestBed.inject(PlansService).plans.set([]); // the committed snapshot may hold real plans: tests must not depend on it
    const fixture = TestBed.createComponent(Home);
    fixture.detectChanges();
    return fixture.nativeElement as HTMLElement;
  }

  it('renders the seven sections in order, alternating dark and light surfaces', () => {
    const el = render();
    const sections = Array.from(el.querySelectorAll('section'));
    const surface = (s: HTMLElement) => (/\b(section-dark|bg-night)\b/.test(s.className) ? 'dark' : 'light');
    expect(sections.map((s) => s.id || s.getAttribute('aria-labelledby'))).toEqual(['hero-title', 'elige', 'servicios', 'sistemas', 'paquetes', 'como', 'contacto']);
    const surfaces = sections.map(surface);
    expect(surfaces).toEqual(['dark', 'light', 'dark', 'light', 'dark', 'light', 'dark']);
    for (let i = 1; i < surfaces.length; i++) expect(surfaces[i]).not.toBe(surfaces[i - 1]);
  });

  it('has a single h1, keeps the news and FAQ anchors, and never shows pending TODO_ text', () => {
    const el = render();
    expect(el.querySelectorAll('h1')).toHaveLength(1);
    expect(el.querySelector('#noticias')).not.toBeNull();
    expect(el.querySelector('#preguntas')).not.toBeNull();
    expect(el.textContent).not.toMatch(/TODO_(?!COPY)/);
    expect(el.querySelector('[style]')).toBeNull(); // no inline styles (CSP style-src 'self')
  });

  it('does not hardcode prices: with an empty catalog no peso amount is shown outside the illustrative mocks', () => {
    const el = render();
    el.querySelectorAll('figure').forEach((f) => f.remove());
    expect(el.textContent).not.toMatch(/\$\s?\d/);
  });

  it('keeps the CFDI claim hidden and makes no invented claims', () => {
    const text = render().textContent ?? '';
    expect(text).not.toMatch(/CFDI|24\/7|uptime|garant|certificad|clientes satisfechos/i);
  });
});
