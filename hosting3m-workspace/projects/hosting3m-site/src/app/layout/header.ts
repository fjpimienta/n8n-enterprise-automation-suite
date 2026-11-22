import { Component, ElementRef, inject, signal, viewChild } from '@angular/core';
import { RouterLink } from '@angular/router';
import { HEADER_CTA, NAV_LINKS } from '../data/nav';
import { SITE, whatsappLink } from '../core/site.config';

@Component({
  selector: 'app-header',
  imports: [RouterLink],
  templateUrl: './header.html',
})
export class Header {
  readonly site = SITE;
  readonly links = NAV_LINKS;
  readonly cta = HEADER_CTA;
  readonly quoteHref = whatsappLink('Hola, quiero una cotización.');
  readonly menuOpen = signal(false);
  private readonly toggleButton = viewChild<ElementRef<HTMLButtonElement>>('toggleButton');

  toggle(): void {
    this.menuOpen.update((open) => !open);
  }

  close(): void {
    this.menuOpen.set(false);
  }

  /** Escape closes the mobile menu and gives the focus back to the button that opened it. */
  onEscape(): void {
    if (!this.menuOpen()) return;
    this.close();
    this.toggleButton()?.nativeElement.focus();
  }
}
