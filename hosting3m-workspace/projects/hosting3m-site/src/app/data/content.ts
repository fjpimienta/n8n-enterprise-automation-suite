import { cfdiClaim } from './cfdi-claim';

/** Static marketing copy (es-MX). Unapproved or unverified claims are TODO_* tokens and block production builds. */

export const SERVICES = [
  { title: 'Servidores VPS', text: 'Servidores virtuales Linux y Windows con la configuración que tu proyecto necesita.' },
  { title: 'n8n y automatización con IA', text: 'Infraestructura para flujos inteligentes con n8n y modelos de lenguaje (LLM), lista para operar.' },
  { title: 'Dominios', text: 'Registro y administración de dominios .com, .mx, .com.mx y nuevas extensiones.' },
  { title: 'Correo electrónico', text: 'Correo con tu propio dominio para que tu equipo se vea profesional.' },
  { title: 'Páginas web', text: 'Sitios modernos, responsivos y optimizados para buscadores, adaptados a tu empresa.' },
  { title: 'Cómputo en la nube', text: 'Aloja tus sistemas y datos en la nube y accede a ellos desde cualquier lugar.' },
] as const;

export const DIFFERENTIATORS: readonly { readonly title: string; readonly text: string }[] = [
  { title: 'Atención local en Mérida', text: 'Hablas con personas de Mérida, Yucatán, por WhatsApp, teléfono o correo.' },
  { title: 'En español', text: 'Propuestas, soporte y documentación en español, sin intermediarios.' },
  { title: 'Automatización administrada', text: 'Operamos tu n8n y tus integraciones para que te concentres en tu negocio.' },
  // CFDI claim card: OFF until the invoicing service exists (flag = the `false` literal below). Keep it a literal: the
  // bundler only drops the dead branch, and with it the TODO_ copy in cfdi-claim.ts, when the condition is a literal.
  // To switch it on, write the real copy in cfdi-claim.ts and change `false` to `true`; with the TODO_ copy still in
  // place the production build fails (TODO guard).
  ...(false /* showCfdiClaim */ ? [cfdiClaim()] : []),
];

export const PROCESS = [
  { title: 'Cuéntanos tu necesidad', text: 'Escríbenos por WhatsApp o con el formulario y platicamos tu proyecto.' },
  { title: 'Recibe una propuesta', text: 'Te enviamos una propuesta clara con alcance y costos.' },
  { title: 'Implementamos contigo', text: 'Ponemos en marcha el servicio y te acompañamos después.' },
] as const;

export const SUITE_MODULES = [
  'Gateway de autenticación multiempresa',
  'Puente CRM',
  'Noticias con IA y búsqueda semántica (RAG)',
  'Flujos de WhatsApp',
  'Servidores MCP para agentes de IA',
  'Aplicaciones Angular 21 y librerías compartidas',
] as const;

/** Real clients, only with the owner's written approval. While empty the trust section is not rendered. */
export const TRUSTED_CLIENTS: readonly { name: string; logo?: string }[] = [];
