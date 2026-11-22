import { DOCUMENT } from '@angular/common';
import { Component, inject } from '@angular/core';
import { NavigationEnd, Router, RouterOutlet } from '@angular/router';
import { filter, skip } from 'rxjs';
import { Header } from './layout/header';
import { Footer } from './layout/footer';
import { WhatsappButton } from './layout/whatsapp-button';
import { CookieBanner } from './sections/cookie-banner';
import { ConsentService } from './core/consent';
import { SeoService } from './core/seo';

@Component({
  selector: 'app-root',
  imports: [RouterOutlet, Header, Footer, WhatsappButton, CookieBanner],
  templateUrl: './app.html',
})
export class App {
  constructor() {
    const document = inject(DOCUMENT);
    inject(Router)
      .events.pipe(
        filter((e): e is NavigationEnd => e instanceof NavigationEnd),
        skip(1), // not on the first load
      )
      .subscribe((e) => {
        // Move keyboard/screen-reader focus to the new page content, except for in-page anchors.
        if (!e.urlAfterRedirects.includes('#')) document.getElementById('main')?.focus({ preventScroll: true });
      });
    inject(SeoService).init();
    inject(ConsentService).init();
  }
}
