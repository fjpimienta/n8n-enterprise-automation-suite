import type { LegalDoc } from './types';

export const PRIVACY: LegalDoc = {
  slug: 'privacy',
  title: 'Aviso de privacidad integral',
  sections: [
    {
      heading: 'Responsable',
      blocks: [
        {
          type: 'p',
          text: '{legalName}, con domicilio en {address}, es responsable del tratamiento de tus datos personales en hosting3m.com. Para cualquier asunto de privacidad escribe a {email} o llama al {phone}.',
        },
      ],
    },
    {
      heading: 'Datos que recabamos',
      blocks: [
        {
          type: 'ul',
          items: [
            'Identificación y contacto: nombre, apellidos, teléfono y correo electrónico, que captura el formulario de contacto.',
            'Tu mensaje y el servicio de tu interés.',
            'Datos de contratación y facturación cuando adquieres un servicio: tu Constancia de Situación Fiscal vigente (con antigüedad no mayor a seis meses), que contiene tu nombre o razón social, RFC y domicilio fiscal, además de tu teléfono y correo electrónico.',
            'Datos técnicos de seguridad: dirección IP y características del navegador, que usa la verificación anti-bots del formulario.',
            'Mensajes y archivos que envías por WhatsApp, solo para atenderte.',
          ],
        },
        { type: 'p', text: 'No solicitamos datos personales sensibles. Te pedimos no incluirlos en tu mensaje.' },
      ],
    },
    {
      heading: 'Finalidades necesarias',
      blocks: [
        {
          type: 'p',
          text: 'Responder tu solicitud y cotizar; contratar, instalar, configurar y dar soporte a los servicios (VPS, dominios, hosting, automatización y páginas web); facturar y cumplir obligaciones fiscales y legales; proteger el sitio contra abuso y fraude.',
        },
      ],
    },
    {
      heading: 'Finalidades que puedes rechazar',
      blocks: [
        {
          type: 'p',
          text: 'Enviarte novedades y promociones, y medir las visitas con Google Analytics. Puedes negarte sin perder ningún servicio: para promociones escribe a {email}, y para Analytics usa el banner de cookies o "Preferencias de cookies" en el pie del sitio.',
        },
      ],
    },
    {
      heading: 'Con quién compartimos tus datos',
      blocks: [
        {
          type: 'table',
          caption: 'Con quién compartimos tus datos',
          columns: ['Tercero', 'Para qué', 'Datos'],
          rows: [
            ['Cloudflare', 'Red de entrega, seguridad y verificación Turnstile', 'IP y datos técnicos del navegador'],
            ['Brevo', 'Envío de correos, como la confirmación de tu mensaje', 'Nombre, correo y contenido del mensaje'],
            ['IONOS', 'Infraestructura que Hosting3M revende: VPS, dominios y hosting', 'Ninguno: Hosting3M contrata los servicios a su propio nombre y no le transmite datos de clientes'],
            ['Meta (WhatsApp)', 'Atención por chat', 'Teléfono y mensajes'],
            ['Google (Analytics)', 'Medición de visitas, solo si aceptas', 'Identificadores en línea y páginas vistas'],
            ['OpenAI', 'Redacción asistida de respuestas a los correos que nos envías', 'Contenido del correo, sin datos de facturación ni información confidencial'],
          ],
        },
        {
          type: 'p',
          text: 'También compartimos datos con autoridades cuando una ley lo exija. Algunos de estos terceros operan fuera de México; al enviarnos tus datos aceptas estas transferencias, necesarias para atenderte, y si no estás de acuerdo puedes manifestarlo escribiendo a {email}. Usamos un modelo de lenguaje de OpenAI solo para redactar respuestas a los correos que nos envías; no le enviamos datos de facturación ni información confidencial. No vendemos tus datos.',
        },
      ],
    },
    {
      heading: 'Derechos ARCO y revocación',
      blocks: [
        {
          type: 'p',
          text: 'Puedes acceder a tus datos, rectificarlos o actualizarlos, cancelarlos u oponerte a su uso, y también revocar tu consentimiento o limitar el uso. Envía tu solicitud a {email} con tu nombre, un medio para responderte, un documento que acredite tu identidad o representación y una descripción clara del derecho que quieres ejercer o de lo que pides. Te responderemos en un máximo de 20 días desde que recibamos tu solicitud y, si procede, la haremos efectiva en los 15 días siguientes; ambos plazos pueden ampliarse una sola vez por un periodo igual si hay causa justificada. Ejercer estos derechos es gratuito: solo podrías cubrir costos de reproducción o envío. Si consideras que se vulneró tu derecho, puedes acudir ante la Secretaría Anticorrupción y Buen Gobierno.',
        },
      ],
    },
    {
      heading: 'Conservación',
      blocks: [
        {
          type: 'p',
          text: 'Conservamos los datos de contacto 24 meses contados desde tu último contacto, y los de contratación y facturación por el plazo que exijan las obligaciones fiscales y legales aplicables. Después los bloqueamos y los suprimimos.',
        },
      ],
    },
    {
      heading: 'Seguridad',
      blocks: [
        {
          type: 'p',
          text: 'Aplicamos medidas técnicas y administrativas para proteger tus datos: conexión cifrada (HTTPS), bases de datos en un servidor privado y protección contra ataques mediante Cloudflare. Si ocurre una vulneración que afecte de forma significativa tus derechos patrimoniales o morales, te lo informaremos de inmediato.',
        },
      ],
    },
    {
      heading: 'Cambios a este aviso',
      blocks: [
        { type: 'p', text: 'Cualquier cambio se publica en esta página con la fecha de actualización. Última actualización: {lastUpdated}.' },
      ],
    },
  ],
};
