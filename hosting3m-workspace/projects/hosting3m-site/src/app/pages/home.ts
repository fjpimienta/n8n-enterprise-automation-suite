import { Component } from '@angular/core';
import { whatsappLink } from '../core/site.config';

/** Phase 1 skeleton: the full section set (services, packages, FAQ, contact...) lands in phase 2. */
@Component({
  selector: 'app-home',
  template: `
    <section class="bg-brand-50 py-16 sm:py-24">
      <div class="container-page">
        <h1 class="max-w-3xl text-4xl font-bold tracking-tight text-brand-900 sm:text-5xl">
          Soluciones en la nube para tu negocio
        </h1>
        <p class="mt-4 max-w-2xl text-lg text-muted">
          VPS, n8n administrado, dominios y correo con soporte local en Mérida. TODO_COPY: promesa final por aprobar.
        </p>
        <div class="mt-8">
          <a class="btn-primary" [href]="quoteHref" target="_blank" rel="noopener noreferrer">Cotiza por WhatsApp</a>
        </div>
      </div>
    </section>
  `,
})
export class Home {
  readonly quoteHref = whatsappLink('Hola, quiero una cotización.');
}
