import { Component } from '@angular/core';
import { whatsappLink } from '../core/site.config';

@Component({
  selector: 'app-whatsapp-button',
  template: `
    <a class="btn-primary fixed bottom-4 right-4 z-40 shadow-lg" [href]="href" target="_blank" rel="noopener noreferrer"
      aria-label="Escríbenos por WhatsApp (se abre en una pestaña nueva)">WhatsApp</a>
  `,
})
export class WhatsappButton {
  readonly href = whatsappLink('Hola, quiero información sobre sus servicios.');
}
