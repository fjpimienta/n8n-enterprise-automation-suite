/**
 * Copy of the home page, grouped per section. Marketing edits are text-only changes in this file.
 * Every string that depends on marketing validation carries a `// MARKETING-REVIEW` comment.
 * Never write prices or client names here: prices come from the catalog (POST /v6/plans).
 */
import { BUSINESS } from '../core/business';
import { SERVICE_LABELS } from './service-labels';
import type { IconName } from '../sections/icon';

// ---- 1 · Hero (dark) ----
export const HERO = {
  eyebrow: 'Mérida, Yucatán · VPS · dominios · automatización', // MARKETING-REVIEW
  title: 'Soluciones en la nube para tu negocio', // MARKETING-REVIEW
  promise: 'Servidores, dominios y automatización con IA, instalados y administrados por una sola persona de confianza en Mérida.', // MARKETING-REVIEW
  ctaPrimary: 'Cotiza por WhatsApp',
  ctaSecondary: 'Elige tu servicio', // MARKETING-REVIEW
  imageAlt: 'Persona trabajando con una laptop bajo una nube con íconos de servidores, inteligencia artificial y sitios web',
  flowCaption: 'flujo.n8n · ejemplo de automatización',
  flowSteps: ['Formulario web', 'Agente IA', 'CRM'],
  facts: [
    { title: 'Infraestructura de IONOS', text: 'Con atención personalizada' }, // MARKETING-REVIEW
    { title: 'Factura de Hosting3M', text: 'Un solo proveedor para todo' }, // MARKETING-REVIEW
    { title: 'Soporte directo', text: BUSINESS.hoursShort },
    { title: 'Respuesta en 1 día hábil', text: 'Por WhatsApp o correo' }, // MARKETING-REVIEW
  ],
} as const;

// ---- 2 · "01 Elige" selector (light) ----
export type NeedId = 'server' | 'domain' | 'automation' | 'web';
export interface NeedOption {
  readonly id: NeedId;
  readonly icon: IconName;
  readonly label: string;
  readonly hint: string;
  /** Catalog family used to look up a price (see core/picker.ts). */
  readonly family: 'vps' | 'domain' | 'automation' | 'web';
  /** Value for the contact form `service` field. */
  readonly service: string;
  readonly fallbackTitle: string;
  readonly text: string;
  readonly cta: string;
}

export const SELECTOR = {
  eyebrow: '01 · ELIGE',
  title: '¿Qué necesitas hoy?', // MARKETING-REVIEW
  intro: 'Elige tu punto de partida y te muestro la mejor opción, con precio claro.', // MARKETING-REVIEW
  recommendLabel: 'Te recomiendo',
  quote: 'Cotiza por WhatsApp',
  options: [
    {
      id: 'server', icon: 'server', label: 'Un servidor', hint: 'VPS para tu sistema o tu sitio', family: 'vps', service: SERVICE_LABELS.vps,
      fallbackTitle: 'Servidor VPS',
      text: 'Servidor virtual para tu sistema o tu sitio. Autoadministrado, o administrado por Hosting3M.', // MARKETING-REVIEW
      cta: 'Cotizar VPS',
    },
    {
      id: 'domain', icon: 'domain', label: 'Un dominio', hint: 'Tu nombre en internet', family: 'domain', service: SERVICE_LABELS.domain,
      fallbackTitle: 'Dominio',
      text: 'Registro y administración de tu dominio, con las extensiones que necesites.', // MARKETING-REVIEW
      cta: 'Cotizar dominio',
    },
    {
      id: 'automation', icon: 'automation', label: 'Automatizar', hint: 'Procesos con n8n e IA', family: 'automation', service: SERVICE_LABELS.automation,
      fallbackTitle: 'n8n administrado',
      text: 'Flujos con n8n y modelos de lenguaje, instalados y operados por Hosting3M.', // MARKETING-REVIEW
      cta: 'Cotizar automatización',
    },
    {
      id: 'web', icon: 'web', label: 'Un sitio web', hint: 'Moderno y optimizado', family: 'web', service: SERVICE_LABELS.web,
      fallbackTitle: 'Página web',
      text: 'Sitios modernos, responsivos y optimizados para buscadores.', // MARKETING-REVIEW
      cta: 'Cotizar sitio web',
    },
  ] as readonly NeedOption[],
} as const;

// ---- 3 · Services (dark) ----
export interface ServiceCard {
  readonly icon: IconName;
  readonly title: string;
  readonly text: string;
  /** Optional mono line (illustrative, never a spec or a price). */
  readonly hint?: string;
  readonly wide?: boolean;
}

export const SERVICES_SECTION = {
  title: 'Todo en un solo lugar', // MARKETING-REVIEW
  intro: 'Instalo, configuro, administro y doy soporte. Tú te dedicas a tu negocio.', // MARKETING-REVIEW
  cards: [
    { icon: 'server', title: 'Servidores VPS', text: 'Servidores virtuales Linux y Windows con la configuración que tu proyecto necesita.', wide: true },
    { icon: 'automation', title: 'n8n y automatización con IA', text: 'Infraestructura para flujos inteligentes con n8n y modelos de lenguaje (LLM), lista para operar.', hint: 'formulario → agente IA → CRM', wide: true },
    { icon: 'domain', title: 'Dominios', text: '.com, .mx, .com.mx y nuevas extensiones.' },
    { icon: 'mail', title: 'Correo electrónico', text: 'Correo con tu propio dominio.' },
    { icon: 'web', title: 'Páginas web', text: 'Modernas, responsivas y optimizadas para buscadores.' },
    { icon: 'cloud', title: 'Cómputo en la nube', text: 'Tus sistemas y datos accesibles desde cualquier lugar.' },
  ] as readonly ServiceCard[],
  // Open-source suite (kept from the previous site, see the project goal): a wide card after the bento grid.
  suite: {
    title: 'Suite de automatización de código abierto',
    text: 'Gateway de autenticación multiempresa, puente CRM, noticias con IA, flujos de WhatsApp y servidores MCP para agentes de IA, con licencia MIT.',
    cta: 'Ver la suite en GitHub',
  },
} as const;

// ---- 6 · "Así de simple" + "Por qué Hosting3M" (light) ----
export const STEPS_SECTION = {
  title: 'Así de simple', // MARKETING-REVIEW
  steps: [
    { title: 'Me cuentas qué necesitas', text: 'Por WhatsApp o por el formulario, sin compromiso.' },
    { title: 'Te cotizo', text: 'Precio claro, en pesos mexicanos y más IVA.' },
    { title: 'Instalo y configuro', text: 'Tu servicio queda listo para usarse.' },
    { title: 'Te doy soporte', text: 'Respondo tu primer mensaje en un día hábil.' },
  ], // MARKETING-REVIEW (the four steps)
} as const;

export const WHY_SECTION = {
  title: 'Por qué Hosting3M', // MARKETING-REVIEW
  items: [
    { title: 'Atención directa', text: 'Hablas con la persona que instala y administra tu servicio, sin tickets ni intermediarios.' },
    { title: 'Instalación y configuración', text: 'En la modalidad administrada, Hosting3M instala, configura, administra y da soporte a tu servicio.' },
    { title: 'Infraestructura de IONOS', text: 'Contratas la misma infraestructura de IONOS, con factura emitida por Hosting3M.' },
  ], // MARKETING-REVIEW (the three reasons)
} as const;

export const FAQ_SECTION = { title: 'Preguntas frecuentes' } as const;

// ---- 5 · "02 Compara" intro (dark; the cards come from the catalog) ----
export const PACKAGES_SECTION = {
  eyebrow: '02 · COMPARA',
  title: 'Paquetes con precio claro', // MARKETING-REVIEW
  intro: 'Precios en pesos mexicanos. Autoadministrado, o administrado por Hosting3M con instalación, configuración y soporte.', // MARKETING-REVIEW
  emptyIntro: 'Armamos tu paquete a la medida. Cuéntanos qué necesitas y te cotizamos por WhatsApp.',
  // MARKETING-REVIEW: section for every plan sold by quote; the line restates the terms of service
  // ("Los servicios con precio "cotiza" se acuerdan por escrito antes de contratar").
  quoteSection: {
    title: 'Servicios a la medida',
    line: 'Precio por cotización: se acuerda por escrito antes de contratar.',
  },
  // MARKETING-REVIEW: restates the terms of service ("servicios propios de automatización con IA, creación de páginas web y correo profesional").
  // Only own-service families appear here. No features, prices, delivery times or limits: those need owner input.
  familyNotes: {
    automation: 'Automatización de procesos con agentes de IA: servicio propio de Hosting3M.',
    web: 'Creación de páginas web: servicio propio de Hosting3M.',
    email: 'Correo profesional: servicio propio de Hosting3M.',
  } as Readonly<Record<string, string>>,
} as const;

// ---- 7 · "03 Cotiza" contact (dark) ----
export const CONTACT_SECTION = {
  eyebrow: '03 · COTIZA',
  title: 'Cuéntame qué necesitas', // MARKETING-REVIEW
  intro: 'Escríbeme y te respondo en un día hábil, dentro del horario de atención. Sin compromiso.', // MARKETING-REVIEW
  whatsapp: 'Cotiza por WhatsApp',
} as const;

export const NEWS_SECTION = { title: 'Noticias' } as const;
