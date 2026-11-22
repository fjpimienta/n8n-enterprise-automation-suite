import { TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { RouterTestingHarness } from '@angular/router/testing';
import { BUSINESS, BUSINESS_ADDRESS_LINE, LEGAL_LAST_UPDATED } from '../../core/business';
import { fillPlaceholders, parseInline } from '../../core/legal-text';
import { routes } from '../../app.routes';
import { LEGAL_DOCS } from '../../data/legal';
import { LegalPage } from './legal-page';

async function render(legal: 'privacy' | 'cookies' | 'terms' | 'deletion') {
  TestBed.configureTestingModule({ providers: [provideRouter([{ path: 'x', component: LegalPage, data: { legal } }])] });
  const harness = await RouterTestingHarness.create();
  await harness.navigateByUrl('/x', LegalPage);
  harness.detectChanges();
  return harness.routeNativeElement as HTMLElement;
}

describe('legal data and inline syntax', () => {
  it('resolves placeholders from the single sources and leaves unknown ones visible', () => {
    expect(fillPlaceholders('{legalName} / {address} / {email} / {phone} / {lastUpdated}')).toBe(
      `${BUSINESS.legalName} / ${BUSINESS_ADDRESS_LINE} / contacto@hosting3m.com / 999 390 2625 / 21 de noviembre de 2026`,
    );
    expect(fillPlaceholders('{nope}')).toBe('{nope}');
  });

  it('parses bold, italic, code and internal links, and ignores external links', () => {
    expect(parseInline('a **b** *c* `d` [e](/x) [f](https://x.y)').map((s) => s.kind)).toEqual(['text', 'bold', 'text', 'italic', 'text', 'code', 'text', 'link', 'text']);
    expect(parseInline('[e](/aviso-de-privacidad)').find((s) => s.kind === 'link')?.href).toBe('/aviso-de-privacidad');
  });

  it('contains no editorial marker and no unresolved placeholder', () => {
    const all = JSON.stringify(LEGAL_DOCS);
    expect(all).not.toMatch(/\[(VERIFICAR|DECIDIR|REVISAR|FECHA DE PUBLICACI)/i);
    for (const key of Object.keys(LEGAL_DOCS) as (keyof typeof LEGAL_DOCS)[]) {
      expect(fillPlaceholders(JSON.stringify(LEGAL_DOCS[key]))).not.toMatch(/\{\w+\}/);
    }
  });

  it('keeps LEGAL_LAST_UPDATED as the single date', () => {
    expect(LEGAL_LAST_UPDATED).toBe('21 de noviembre de 2026');
  });
});

describe('LegalPage', () => {
  it('privacy: one h1, h2 sections, owner data from business.ts, the third-party table and the last update date', async () => {
    const el = await render('privacy');
    expect(el.querySelectorAll('h1')).toHaveLength(1);
    expect(el.querySelector('h1')?.textContent).toBe('Aviso de privacidad integral');
    const h2 = Array.from(el.querySelectorAll('h2')).map((h) => h.textContent);
    expect(h2).toEqual(['Responsable', 'Datos que recabamos', 'Finalidades necesarias', 'Finalidades que puedes rechazar', 'Con quién compartimos tus datos', 'Derechos ARCO y revocación', 'Conservación', 'Seguridad', 'Cambios a este aviso']);
    const text = el.textContent ?? '';
    expect(text).toContain(`${BUSINESS.legalName}, con domicilio en ${BUSINESS_ADDRESS_LINE}`);
    expect(text).toContain('llama al 999 390 2625');
    expect(text).toContain('en un máximo de 20 días');
    expect(text).toContain('los 15 días siguientes');
    expect(text).toContain('Última actualización: 21 de noviembre de 2026.');
    expect(text).not.toMatch(/\{\w+\}|\[VERIFICAR|TODO_/);
    expect(el.querySelectorAll('li')).toHaveLength(5);
  });

  it('privacy: the third-party table is accessible (caption, th scope) and lists the six parties of the draft', async () => {
    const el = await render('privacy');
    const table = el.querySelector('table')!;
    expect(table.querySelector('caption')?.textContent).toBe('Con quién compartimos tus datos');
    expect(Array.from(table.querySelectorAll('thead th')).map((th) => [th.textContent, th.getAttribute('scope')])).toEqual([['Tercero', 'col'], ['Para qué', 'col'], ['Datos', 'col']]);
    const rowHeaders = Array.from(table.querySelectorAll('tbody th'));
    expect(rowHeaders.map((th) => th.textContent?.trim())).toEqual(['Cloudflare', 'Brevo', 'IONOS', 'Meta (WhatsApp)', 'Google (Analytics)', 'OpenAI']);
    expect(rowHeaders.every((th) => th.getAttribute('scope') === 'row')).toBe(true);
    expect(table.textContent).toContain('Ninguno: Hosting3M contrata los servicios a su propio nombre');
    expect(table.textContent).not.toContain('Neubox'); // Neubox is not in the table of the draft
    // stacked layout on mobile reads the labels from data-label
    expect(table.querySelector('tbody tr td')?.getAttribute('data-label')).toBe('Para qué');
  });

  it('cookies: the five-column table of the draft with ga id and consent key from their sources', async () => {
    const el = await render('cookies');
    expect(el.querySelectorAll('h1')).toHaveLength(1);
    const table = el.querySelector('table')!;
    expect(Array.from(table.querySelectorAll('thead th')).map((th) => th.textContent)).toEqual(['Nombre', 'Proveedor', 'Finalidad', 'Duración', 'Requiere tu consentimiento']);
    const names = Array.from(table.querySelectorAll('tbody th')).map((th) => th.textContent?.trim());
    expect(names.map((n) => n?.replace(/\s+/g, ' '))).toEqual(['_ga', '_ga_MVJRDZ7TD8', 'Cookies de Cloudflare y Turnstile', 'h3m_cookie_consent_v1 (almacenamiento local)']);
    expect(table.querySelectorAll('tbody tr')).toHaveLength(4);
    expect(table.querySelectorAll('code').length).toBe(3);
    expect(el.textContent).toContain('"Preferencias de cookies" en el pie del sitio');
    expect(el.querySelector('strong')?.textContent).toBe('Aceptar');
  });

  it('terms: all sections, links to privacy and cookies, and the last update date', async () => {
    const el = await render('terms');
    expect(el.querySelectorAll('h1')).toHaveLength(1);
    expect(el.querySelectorAll('h2')).toHaveLength(14);
    const hrefs = Array.from(el.querySelectorAll('a')).map((a) => a.getAttribute('href'));
    expect(hrefs).toEqual(['/aviso-de-privacidad', '/politica-de-cookies']);
    const text = el.textContent ?? '';
    expect(text).toContain('Ningún servicio se renueva de forma automática');
    expect(text).toContain('con 30 días de anticipación');
    expect(text).toContain('tribunales competentes de Mérida, Yucatán');
    expect(text).toContain('Última actualización: 21 de noviembre de 2026.');
    expect(text).toContain(`pertenecen a ${BUSINESS.legalName}`);
    expect(el.querySelector('em')?.textContent).toBe('autoadministrado');
  });
});

describe('data deletion page (/eliminardatosusuarios)', () => {
  it('has one h1, the privacy-notice wording and the owner data from business.ts', async () => {
    const el = await render('deletion');
    expect(el.querySelectorAll('h1')).toHaveLength(1);
    expect(el.querySelector('h1')?.textContent).toBe('Eliminación de datos de usuario');
    expect(el.querySelectorAll('h2')).toHaveLength(6);
    expect(el.querySelector('h3')).toBeNull(); // no broken hierarchy
    const text = el.textContent ?? '';
    expect(text).toContain(BUSINESS.email);
    expect(text).toContain(BUSINESS.phone);
    expect(text).toContain('"Solicitud de eliminación de datos de usuario"');
    expect(text).toContain('un máximo de 20 días');
    expect(text).toContain('los 15 días siguientes');
    expect(text).toContain('una sola vez');
    expect(text).toContain('es gratuito');
    expect(text).toContain('costos de reproducción o envío');
    expect(text).toContain('Primero los bloqueamos y después los suprimimos');
    expect(text).toContain('24 meses contados desde tu último contacto');
    expect(text).toContain('obligaciones fiscales y legales aplicables');
    expect(text).toContain(`${BUSINESS.legalName}, con domicilio en ${BUSINESS_ADDRESS_LINE}`);
    expect(text).toContain('Secretaría Anticorrupción y Buen Gobierno');
    expect(text).toContain(`Última actualización: ${LEGAL_LAST_UPDATED}.`);
  });

  it('links to the privacy notice and never mentions Facebook, 30 days, automatic deletion or a marker', async () => {
    const el = await render('deletion');
    expect(Array.from(el.querySelectorAll('a')).map((a) => a.getAttribute('href'))).toEqual(['/aviso-de-privacidad']);
    const text = el.textContent ?? '';
    expect(text).not.toMatch(/facebook|30 días|automátic|\{\w+\}|\[VERIFICAR|TODO_/i);
    expect(JSON.stringify(LEGAL_DOCS.deletion)).not.toMatch(/facebook|30 días|automátic/i);
  });
});

describe('legal routes', () => {
  const find = (path: string) => routes.find((r) => r.path === path);

  it('has the three new indexable pages with a unique title and description each', () => {
    const pages = ['aviso-de-privacidad', 'politica-de-cookies', 'terminos-y-condiciones'].map((p) => find(p)!);
    expect(pages.every((r) => r && r.loadComponent)).toBe(true);
    expect(new Set(pages.map((r) => r.title)).size).toBe(3);
    expect(new Set(pages.map((r) => (r.data as { description: string }).description)).size).toBe(3);
  });

  it('keeps the old links alive with redirects to the new names', () => {
    expect(find('politica-de-privacidad')?.redirectTo).toBe('aviso-de-privacidad');
    expect(find('condiciones-de-servicio')?.redirectTo).toBe('terminos-y-condiciones');
    expect(find('privacy')?.redirectTo).toBe('aviso-de-privacidad');
    // Meta depends on this exact path: it stays a real page (no rename, no redirect).
    const deletion = find('eliminardatosusuarios')!;
    expect(deletion.loadComponent).toBeDefined();
    expect(deletion.redirectTo).toBeUndefined();
    expect((deletion.data as { legal: string; description: string }).legal).toBe('deletion');
    expect(String(deletion.title)).toContain('Eliminación de datos de usuario');
  });
});
