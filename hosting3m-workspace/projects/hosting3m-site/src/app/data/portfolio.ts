/**
 * Portfolio page: the two own products, with no client names, logos, real screenshots, client counts or metrics.
 * Mock screens are the same illustrative components used in the systems section (fictitious data).
 */
import { DEMO_CTAS, DEMO_TABS, DemoTab, SYSTEMS_SECTION } from './systems-demo';

export interface PortfolioItem {
  readonly id: 'hotel' | 'agro';
  readonly title: string;
  readonly since: string;
  readonly text: string;
  readonly mocks: readonly DemoTab[];
}

export const PORTFOLIO = {
  title: 'Portafolio',
  intro: 'Sistemas propios desarrollados por Hosting3M, ya en operación y en mejora continua.', // MARKETING-REVIEW
  illustrative: SYSTEMS_SECTION.illustrative,
  cta: 'Pedir demo',
  items: [
    {
      id: 'hotel',
      title: 'ERP hotelero',
      since: DEMO_TABS[0].since,
      text: 'Habitaciones, reservas, check-in y check-out, mantenimiento, inventario y caja, con un asistente de chat en evolución.', // MARKETING-REVIEW
      mocks: ['hotel'],
    },
    {
      id: 'agro',
      title: 'Agro ERP con asistente de IA',
      since: DEMO_TABS[1].since,
      text: 'Capitalización y rendimiento del hato, censo por arete o RFID, palpaciones y cumplimiento normativo (UPP y licencias PSG), con asistente por chat web y por WhatsApp.', // MARKETING-REVIEW
      mocks: ['agro', 'whatsapp'],
    },
  ] as readonly PortfolioItem[],
  demo: DEMO_CTAS,
} as const;
