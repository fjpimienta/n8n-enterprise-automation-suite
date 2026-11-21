/** Header navigation. Labels are copy (MARKETING-REVIEW); fragments must match the section ids on the home page. */
export interface NavLink {
  readonly label: string;
  readonly fragment: string;
}

// MARKETING-REVIEW: menu labels and order
export const NAV_LINKS: readonly NavLink[] = [
  { label: 'Servicios', fragment: 'servicios' },
  { label: 'Paquetes', fragment: 'paquetes' },
  { label: 'Sistemas', fragment: 'sistemas' },
  { label: 'Noticias', fragment: 'noticias' },
  { label: 'Contacto', fragment: 'contacto' },
];

// MARKETING-REVIEW: header call to action
export const HEADER_CTA = { desktop: 'Cotiza por WhatsApp', mobile: 'Cotiza' } as const;
