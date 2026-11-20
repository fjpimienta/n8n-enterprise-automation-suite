import { Component, inject } from '@angular/core';
import { RouterOutlet } from '@angular/router';
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
    inject(SeoService).init();
    inject(ConsentService).init();
  }
}
