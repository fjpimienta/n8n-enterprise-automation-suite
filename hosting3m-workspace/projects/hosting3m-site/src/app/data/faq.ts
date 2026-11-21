import { BUSINESS } from '../core/business';

export interface FaqItem {
  readonly q: string;
  readonly a: string;
}

/** Frequently asked questions. Marketing edits are text-only changes here. */
export const FAQ: readonly FaqItem[] = [
  {
    q: '¿Qué diferencia hay entre contratar con Hosting3M y contratar directo con IONOS?',
    a: 'Contratas la misma infraestructura de IONOS, con una persona de contacto directa. En la modalidad administrada, Hosting3M instala, configura, administra y da soporte a tu servicio. En la autoadministrada pagas el precio del plan y tú lo administras; la instalación inicial se cotiza aparte. Además, Hosting3M te emite la factura.',
  },
  // MARKETING-REVIEW: the three entries below come from the design artboard and are not approved copy yet.
  { q: '¿Los precios incluyen IVA?', a: 'Cada precio indica si incluye IVA o si se muestra más IVA. Los precios están en pesos mexicanos.' },
  { q: '¿Cada cuánto se paga?', a: 'El periodo de cobro (mensual, anual o pago único) aparece en cada paquete.' },
  { q: '¿En cuánto tiempo me responden?', a: 'Respondo tu primer mensaje en un día hábil, dentro del horario de atención: ' + BUSINESS.hoursText + '.' },
];
