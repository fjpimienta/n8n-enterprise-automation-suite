/** Values of the contact form `service` field used by the redesign. The first four must match CONTACT_SERVICES. */
export const SERVICE_LABELS = {
  vps: 'Renta de Servidores VPS',
  domain: 'Registro de Dominios',
  automation: 'Automatización de Procesos con Agentes IA',
  web: 'Creación de Páginas Web',
  /** Demo requests: not in the static list; the contact form accepts them through ContactPrefill. */
  demoHotel: 'ERP hotelero (solicitud de demo)',
  demoAgro: 'Agro ERP (solicitud de demo)',
} as const;
