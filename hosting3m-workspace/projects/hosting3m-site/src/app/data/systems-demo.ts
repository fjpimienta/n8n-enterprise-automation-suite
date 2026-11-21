/**
 * "Míralo en acción": copy and mock-screen text for the three tabs. The mocks are static, built with HTML/CSS, and use only
 * "Hotel Demo" and "Rancho Demo" with fictitious data (labeled "Ejemplo ilustrativo"). They never call any ERP API.
 * Allowed statements: hotel ERP in operation since January 2026, Agro ERP since November 2026, both keep improving,
 * hotel chat assistant "en evolución". Security wording: signed tokens and data separated per company.
 */
import { SERVICE_LABELS } from './service-labels';

export type DemoTab = 'hotel' | 'agro' | 'whatsapp';

export const SYSTEMS_SECTION = {
  eyebrow: 'SISTEMAS PROPIOS',
  title: 'Míralo en acción', // MARKETING-REVIEW
  intro:
    'Dos sistemas desarrollados por Hosting3M y ya en operación: un ERP para hoteles, desde enero de 2026, y un ERP agropecuario con asistente de IA, desde noviembre de 2026. Siguen mejorando.', // MARKETING-REVIEW
  illustrative: 'Ejemplo ilustrativo · datos ficticios',
  tablistLabel: 'Sistemas de Hosting3M',
} as const;

export interface DemoText {
  readonly id: DemoTab;
  readonly tab: string;
  readonly title: string;
  readonly since: string;
  readonly lead: string;
  readonly bullets: readonly string[];
  readonly mockLabel: string;
}

export const DEMO_TABS: readonly DemoText[] = [
  {
    id: 'hotel',
    tab: 'ERP hotelero',
    title: 'ERP hotelero',
    since: 'En operación desde enero de 2026',
    lead: 'Habitaciones, reservas, huéspedes, personal, inventario y caja en un solo lugar, y desde el celular.', // MARKETING-REVIEW
    bullets: [
      'Estado de cada habitación a la vista, con próxima reserva',
      'Check-in, reservas y revisión de salida con lista de control',
      'Mantenimiento, rondines de calidad e inventario por habitación',
      'Caja y finanzas por día, semana, mes o año, con reporte en PDF',
      'Asistente de chat para crear reservas, check-in y check-out (en evolución)',
    ], // MARKETING-REVIEW (feature list)
    mockLabel: 'Pantalla de ejemplo del ERP hotelero, Hotel Demo',
  },
  {
    id: 'agro',
    tab: 'Agro ERP · chat web',
    title: 'Agro ERP con asistente de IA',
    since: 'En operación desde noviembre de 2026',
    lead: 'Controla tu hato y tus gastos, y pregúntale al asistente en lenguaje normal. En el chat web ya vienen asignadas tu empresa y tu UPP.', // MARKETING-REVIEW
    bullets: [
      'Resumen de capitalización y rendimiento del hato',
      'Censo por arete o chip RFID, con módulos de cría, engorda y reproducción',
      'Palpaciones, comparación de campañas y seguimiento de vacías, con exportación a CSV',
      'Seguimiento de cumplimiento normativo (UPP y licencias PSG)',
      'Asistente que consulta y registra por chat',
    ], // MARKETING-REVIEW (feature list)
    mockLabel: 'Conversación de ejemplo con el asistente de IA del Agro ERP, Rancho Demo',
  },
  {
    id: 'whatsapp',
    tab: 'Agro ERP · WhatsApp',
    title: 'Lo mismo, desde WhatsApp',
    since: 'En operación desde noviembre de 2026',
    lead: 'El sistema reconoce tu número de teléfono y lo liga a tu empresa y a tus UPP. Si tienes más de una, te pregunta a cuál se refiere antes de registrar.', // MARKETING-REVIEW
    bullets: [
      'Consultas y registros sin abrir el sistema',
      'Cada número queda ligado solo a su empresa y a sus UPP',
      'Autenticación con tokens firmados y datos separados por empresa',
    ], // MARKETING-REVIEW (feature list and security wording)
    mockLabel: 'Conversación de ejemplo por WhatsApp con el asistente del Agro ERP, Rancho Demo',
  },
];

export const HOTEL_MOCK = {
  name: 'Hotel Demo',
  chips: [
    { label: 'Disponible', active: true },
    { label: 'Ocupada' },
    { label: 'Limpieza' },
    { label: 'Mantenimiento' },
  ] as readonly { readonly label: string; readonly active?: boolean }[],
  rooms: [
    { number: '2', type: 'Sencilla', status: '● DISPONIBLE', tone: 'ok' },
    { number: '6', type: 'Doble', status: '● SALE HOY', tone: 'warn' },
    { number: '11', type: 'Sencilla', status: 'Próxima reserva: 18 dic', tone: 'note' },
  ],
  actions: [
    { label: 'Registrar check-in', tone: 'blue' },
    { label: 'Realizar rondín', tone: 'green' },
  ],
  money: [
    { label: 'Ingresos', value: '$12,400', tone: 'in' },
    { label: 'Gastos', value: '$3,150', tone: 'out' },
    { label: 'Utilidad', value: '$9,250', tone: 'net' },
  ],
} as const;

export interface ChatLine {
  readonly from: 'user' | 'bot';
  readonly text: string;
}

export const AGRO_CHAT = {
  title: 'Asistente IA · Agro ERP',
  status: '● Online',
  lines: [
    { from: 'user', text: 'Status del animal 9999200021' },
    { from: 'bot', text: 'El animal con arete 9999200021 es una vaca bovina con estatus actual VACÍA. No tiene peso registrado. ¿Deseas hacer otra consulta?' },
    { from: 'user', text: 'Registra un gasto de combustible por 580' },
    { from: 'bot', text: 'Se registró un gasto de combustible por $580 en Rancho Demo. ¿Quieres registrar otro?' },
  ] as readonly ChatLine[],
} as const;

export const WHATSAPP_CHAT = {
  title: 'Agro ERP · asistente',
  subtitle: 'por WhatsApp',
  lines: [
    { from: 'user', text: 'Registra un gasto de combustible por 580' },
    { from: 'bot', text: 'Tu número está ligado a 2 UPP. ¿Para cuál es el registro?\n1) Ganadería\n2) Palma' },
    { from: 'user', text: '1' },
    { from: 'bot', text: 'Listo: gasto de combustible por $580 registrado en Ganadería.' },
  ] as readonly ChatLine[],
} as const;

export const DEMO_CTAS = {
  hotel: { label: 'Pedir demo del ERP hotelero', service: SERVICE_LABELS.demoHotel, message: 'Quiero una demo del ERP hotelero.' },
  agro: { label: 'Pedir demo del Agro ERP', service: SERVICE_LABELS.demoAgro, message: 'Quiero una demo del Agro ERP.' },
} as const;
