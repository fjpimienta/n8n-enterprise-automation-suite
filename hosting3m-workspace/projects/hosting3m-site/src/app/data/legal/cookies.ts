import type { LegalDoc } from './types';

export const COOKIES: LegalDoc = {
  slug: 'cookies',
  title: 'Política de cookies',
  sections: [
    {
      blocks: [
        {
          type: 'p',
          text: 'El sitio no carga Google Analytics ni guarda cookies de analítica hasta que pulsas **Aceptar** en el banner. Si pulsas **Rechazar**, no se carga y se borran las cookies de Analytics que existieran.',
        },
        {
          type: 'table',
          caption: 'Cookies y almacenamiento local que usa el sitio',
          columns: ['Nombre', 'Proveedor', 'Finalidad', 'Duración', 'Requiere tu consentimiento'],
          rows: [
            ['`_ga`', 'Google Analytics', 'Distinguir visitantes para estadísticas', 'Hasta 2 años', 'Sí'],
            ['`_ga_{gaId}`', 'Google Analytics', 'Conservar el estado de la sesión de medición', 'Hasta 2 años', 'Sí'],
            ['Cookies de Cloudflare y Turnstile', 'Cloudflare', 'Seguridad y verificación anti-bots del formulario', 'Según Cloudflare', 'No, son técnicas'],
            ['`{consentKey}` (almacenamiento local)', 'Hosting3M', 'Recordar si aceptaste o rechazaste', 'Hasta que lo borres', 'No, es técnica'],
          ],
        },
        {
          type: 'p',
          text: 'Puedes cambiar tu decisión en cualquier momento con "Preferencias de cookies" en el pie del sitio, o borrando los datos del sitio en tu navegador. Rechazar las cookies de analítica no limita ninguna función del sitio.',
        },
      ],
    },
  ],
};
