import { Component, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { SITE } from '../core/site.config';

@Component({
  selector: 'app-header',
  imports: [RouterLink],
  templateUrl: './header.html',
})
export class Header {
  readonly site = SITE;
  readonly menuOpen = signal(false);
  readonly links = [
    { label: 'Servicios', fragment: 'servicios' },
    { label: 'Paquetes', fragment: 'paquetes' },
    { label: 'Suite open source', fragment: 'suite' },
    { label: 'Noticias', fragment: 'noticias' },
    { label: 'Contacto', fragment: 'contacto' },
  ];

  toggle(): void {
    this.menuOpen.update((open) => !open);
  }

  close(): void {
    this.menuOpen.set(false);
  }
}
