import { ChangeDetectionStrategy, Component } from '@angular/core';
import { RouterLink } from '@angular/router';
import { ContactForm } from '../sections/contact-form';
import { PlansSection } from '../sections/plans-section';
import { NewsSection } from '../sections/news-section';
import { DIFFERENTIATORS, PROCESS, SERVICES, SUITE_MODULES, TRUSTED_CLIENTS } from '../data/content';
import faq from '../data/faq.json';
import { SITE, whatsappLink } from '../core/site.config';

@Component({
  selector: 'app-home',
  imports: [RouterLink, ContactForm, NewsSection, PlansSection],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './home.html',
})
export class Home {
  readonly site = SITE;
  readonly quoteHref = whatsappLink('Hola, quiero una cotización.');
  readonly services = SERVICES;
  readonly differentiators = DIFFERENTIATORS;
  readonly process = PROCESS;
  readonly suiteModules = SUITE_MODULES;
  readonly clients = TRUSTED_CLIENTS;
  readonly faq = faq;
}
