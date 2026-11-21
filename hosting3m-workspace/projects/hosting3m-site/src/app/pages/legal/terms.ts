import { Component } from '@angular/core';
import { BUSINESS } from '../../core/business';
import { SITE } from '../../core/site.config';

@Component({
  selector: 'app-terms',
  template: `
    <article class="container-page legal-prose py-12">
      <h1>Condiciones de servicio</h1>
      <p class="updated">Última actualización: 29/08/2025</p>
      <p>Bienvenido a Hosting3M. Al utilizar nuestros servicios, aplicaciones o canales de comunicación (incluyendo WhatsApp Business y Facebook), usted acepta estas Condiciones del Servicio.</p>
      <h2>1. Aceptación de las condiciones</h2>
      <p>Al acceder o utilizar nuestros servicios, usted declara que ha leído, entendido y aceptado estas Condiciones. Si no está de acuerdo, le pedimos que no utilice nuestros servicios.</p>
      <h2>2. Uso de los servicios</h2>
      <ul>
        <li>El usuario se compromete a proporcionar información veraz y actualizada al utilizar nuestros servicios.</li>
        <li>No está permitido utilizar nuestros servicios para fines ilegales, fraudulentos o que puedan afectar a terceros.</li>
        <li>El uso de nuestros servicios está sujeto a las leyes y regulaciones aplicables.</li>
      </ul>
      <h2>3. Comunicación a través de WhatsApp Business y Facebook</h2>
      <ul>
        <li>Cuando se comunique con nosotros por estos canales, la información compartida se usará únicamente para brindar atención, soporte o la prestación del servicio contratado.</li>
        <li>WhatsApp y Facebook son plataformas externas con sus propias políticas y condiciones, que recomendamos revisar.</li>
      </ul>
      <h2>4. Propiedad intelectual</h2>
      <p>Todos los contenidos, marcas, logotipos y materiales relacionados con nuestros servicios son propiedad de {{ business.legalName }}, salvo que se indique lo contrario. No está permitido su uso sin autorización expresa.</p>
      <h2>5. Responsabilidad</h2>
      <ul>
        <li>Hosting3M no será responsable por daños directos o indirectos derivados del mal uso de los servicios.</li>
        <li>No garantizamos disponibilidad ininterrumpida, dado que pueden depender de factores externos o de plataformas de terceros (por ejemplo, WhatsApp o Facebook).</li>
      </ul>
      <h2>6. Modificaciones</h2>
      <p>Podemos actualizar estas Condiciones en cualquier momento. Los cambios entrarán en vigor una vez publicados en esta página.</p>
      <h2>7. Contacto</h2>
      <p>Si tiene dudas o comentarios sobre estas Condiciones del Servicio, puede comunicarse con nosotros en:<br />Hosting3M<br />Correo: {{ site.emails.general }}<br />Teléfono: {{ site.phoneDisplay }}</p>
    </article>
  `,
})
export class Terms {
  readonly site = SITE;
  readonly business = BUSINESS;
}
