import type { LegalDoc } from './types';

/**
 * Data deletion instructions. The URL /eliminardatosusuarios is referenced by Meta: never rename or redirect it.
 * Wording reuses the privacy notice (data/legal/privacy.ts, ARCO and Conservación sections). There is no automatic
 * deletion and no Facebook Login: requests are handled by hand by the controller.
 */
export const DELETION: LegalDoc = {
  slug: 'deletion',
  title: 'Eliminación de datos de usuario',
  sections: [
    {
      heading: 'Qué puedes solicitar',
      blocks: [
        {
          type: 'p',
          text: 'Puedes solicitar la cancelación y supresión de tus datos personales, incluidos los que enviaste por el formulario de contacto o por WhatsApp. Es el derecho de cancelación descrito en el [aviso de privacidad](/aviso-de-privacidad).',
        },
      ],
    },
    {
      heading: 'Cómo solicitarlo',
      blocks: [
        {
          type: 'p',
          text: 'Escribe a {email} o llama al {phone}, con el asunto "Solicitud de eliminación de datos de usuario". Incluye tu nombre, un medio para responderte, un documento que acredite tu identidad o representación y una descripción clara de lo que pides.',
        },
      ],
    },
    {
      heading: 'Plazos y costo',
      blocks: [
        {
          type: 'p',
          text: 'Te responderemos en un máximo de 20 días desde que recibamos tu solicitud y, si procede, la haremos efectiva en los 15 días siguientes; ambos plazos pueden ampliarse una sola vez por un periodo igual si hay causa justificada. Ejercer este derecho es gratuito: solo podrías cubrir costos de reproducción o envío.',
        },
      ],
    },
    {
      heading: 'Qué ocurre con tus datos',
      blocks: [
        {
          type: 'p',
          text: 'Primero los bloqueamos y después los suprimimos. Conservamos los datos de contacto 24 meses contados desde tu último contacto, y los de contratación y facturación por el plazo que exijan las obligaciones fiscales y legales aplicables.',
        },
      ],
    },
    {
      heading: 'Responsable',
      blocks: [{ type: 'p', text: '{legalName}, con domicilio en {address}.' }],
    },
    {
      heading: 'Autoridad',
      blocks: [
        { type: 'p', text: 'Si consideras que se vulneró tu derecho, puedes acudir ante la Secretaría Anticorrupción y Buen Gobierno.' },
        { type: 'p', text: 'Última actualización: {lastUpdated}.' },
      ],
    },
  ],
};
