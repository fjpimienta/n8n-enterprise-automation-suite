import { Component } from '@angular/core';
import { SITE } from '../../core/site.config';

/** Public data-deletion URL required by Meta for "Iniciar sesión con Facebook". Keep the URL stable. */
@Component({
  selector: 'app-deletion',
  template: `
    <article class="container-page legal-prose py-12">
      <h1>Política de eliminación de datos de usuario</h1>
      <p class="updated">Última actualización: 29/08/2025</p>
      <p>Esta política detalla cómo puedes solicitar la eliminación de los datos que nuestra aplicación ha recopilado al iniciar sesión con Facebook.</p>
      <h2>Opciones para la eliminación de datos</h2>
      <h2>Solicitud por correo electrónico</h2>
      <p>Puedes enviarnos una solicitud para la eliminación de tus datos directamente. Procesaremos tu solicitud y eliminaremos toda la información de usuario asociada a tu cuenta dentro de un plazo de 30 días.</p>
      <ul>
        <li><strong>Asunto del correo:</strong> Solicitud de Eliminación de Datos de Usuario</li>
        <li><strong>Enviar a:</strong> <a [href]="'mailto:' + site.emails.general">{{ site.emails.general }}</a></li>
        <li><strong>Cuerpo del correo:</strong> Por favor, incluye tu <strong>nombre completo</strong> y el <strong>correo electrónico</strong> asociado a tu cuenta de Facebook para que podamos identificarte y procesar tu solicitud.</li>
      </ul>
      <p><strong>Nota importante:</strong> después de eliminar tus datos, ya no podrás utilizar la función «Iniciar sesión con Facebook» ni ninguna característica de la aplicación que requiera tu información de usuario de Facebook.</p>
    </article>
  `,
})
export class Deletion {
  readonly site = SITE;
}
