import { Component } from '@angular/core';
import { SITE } from '../../core/site.config';

@Component({
  selector: 'app-privacy',
  template: `
    <article class="container-page legal-prose py-12">
      <h1>Política de privacidad</h1>
      <p class="updated">Última actualización: 30/08/2025</p>
      <p>En Hosting3M nos comprometemos a proteger la privacidad de nuestros clientes, usuarios y visitantes. Esta Política de Privacidad explica cómo recopilamos, usamos y protegemos la información personal que obtenemos a través de nuestros servicios, aplicaciones y canales de comunicación, incluyendo WhatsApp Business y Facebook.</p>
      <h2>1. Información que recopilamos</h2>
      <p>Podemos recopilar la siguiente información:</p>
      <ul>
        <li>Datos de contacto: nombre, correo electrónico, número de teléfono.</li>
        <li>Información necesaria para la prestación de servicios: pedidos, facturación, historial de interacciones.</li>
        <li>Información técnica: dirección IP, tipo de dispositivo, navegador, y datos de uso de la aplicación o página web.</li>
        <li>Mensajes y archivos compartidos mediante nuestros canales de comunicación (por ejemplo, WhatsApp Business), únicamente para fines de soporte y atención.</li>
      </ul>
      <h2>2. Uso de la información</h2>
      <p>Utilizamos los datos recopilados para:</p>
      <ul>
        <li>Brindar y mejorar nuestros productos y servicios.</li>
        <li>Proporcionar atención al cliente y soporte técnico.</li>
        <li>Enviar notificaciones relacionadas con el servicio, actualizaciones o promociones (cuando el usuario haya dado su consentimiento).</li>
        <li>Cumplir con requisitos legales y regulatorios.</li>
      </ul>
      <h2>3. Compartición de información</h2>
      <p>No vendemos, alquilamos ni compartimos datos personales con terceros, salvo en los siguientes casos:</p>
      <ul>
        <li>Cuando sea necesario para prestar el servicio (por ejemplo, proveedores de tecnología o logística).</li>
        <li>Para cumplir obligaciones legales o responder a requerimientos de autoridades.</li>
        <li>Con consentimiento expreso del usuario.</li>
      </ul>
      <h2>4. Seguridad de la información</h2>
      <p>Implementamos medidas técnicas, administrativas y organizativas para proteger la información personal contra accesos no autorizados, pérdida, uso indebido o divulgación.</p>
      <h2>5. Conservación de datos</h2>
      <p>Conservamos los datos personales únicamente durante el tiempo necesario para cumplir con los fines descritos en esta política, o según lo exijan las leyes aplicables.</p>
      <h2>6. Derechos del usuario</h2>
      <p>Los usuarios tienen derecho a:</p>
      <ul>
        <li>Acceder, rectificar o eliminar sus datos personales.</li>
        <li>Oponerse o limitar el tratamiento de sus datos.</li>
        <li>Retirar el consentimiento otorgado en cualquier momento.</li>
      </ul>
      <p>Para ejercer estos derechos, puede contactarnos en: {{ site.emails.general }} / {{ site.phoneDisplay }}.</p>
      <h2>7. Uso de WhatsApp Business y Facebook</h2>
      <p>Cuando se comunique con nosotros a través de WhatsApp Business o Facebook:</p>
      <ul>
        <li>La información compartida se utilizará únicamente para atender su solicitud o proveer el servicio.</li>
        <li>Reconocemos que WhatsApp y Facebook son plataformas externas y cuentan con sus propias Políticas de Privacidad, las cuales recomendamos revisar.</li>
      </ul>
      <h2>8. Contacto</h2>
      <p>Si tiene preguntas sobre esta Política de Privacidad, puede escribirnos a:<br />Hosting3M<br />Correo: {{ site.emails.general }}<br />Teléfono: {{ site.phoneDisplay }}</p>
    </article>
  `,
})
export class Privacy {
  readonly site = SITE;
}
