import { ChangeDetectionStrategy, Component } from '@angular/core';
import { BUSINESS } from '../core/business';
import { SITE, whatsappLink } from '../core/site.config';
import { CONTACT_SECTION } from '../data/home-copy';
import { ContactForm } from './contact-form';

/** Section 7 (dark): "03 Cotiza". Wraps the existing contact form without touching its logic. */
@Component({
  selector: 'app-contact-section',
  imports: [ContactForm],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './contact-section.html',
})
export class ContactSection {
  readonly copy = CONTACT_SECTION;
  readonly site = SITE;
  readonly business = BUSINESS;
  readonly quoteHref = whatsappLink('Hola, quiero una cotización.');
}
