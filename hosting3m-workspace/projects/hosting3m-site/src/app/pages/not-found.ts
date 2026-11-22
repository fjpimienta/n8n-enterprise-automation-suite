import { Component } from '@angular/core';
import { RouterLink } from '@angular/router';

@Component({
  selector: 'app-not-found',
  imports: [RouterLink],
  template: `
    <section class="container-page py-16">
      <h1 class="text-3xl font-bold text-brand-900">Página no encontrada</h1>
      <p class="mt-4 text-muted">La dirección que buscas no existe o cambió.</p>
      <a routerLink="/" class="btn-primary mt-6">Ir al inicio</a>
    </section>
  `,
})
export class NotFound {}
