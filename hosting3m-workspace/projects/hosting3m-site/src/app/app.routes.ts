import { Routes } from '@angular/router';

const SITE_NAME = 'Hosting3M';

/**
 * Legacy URLs are redirected by nginx first (see docs/nginx-legacy-redirects.conf).
 * The redirects below are a client-side safety net only.
 * `/webcard` and `/g` are Sitejet asset folders on the server: they must NOT be routed here.
 */
export const routes: Routes = [
  {
    path: '',
    pathMatch: 'full',
    title: `${SITE_NAME} | Servicios en la nube, VPS y automatización con n8n`,
    data: {
      jsonLd: 'home',
      description:
        'Hosting3M en Mérida, Yucatán: VPS, n8n administrado, dominios y correo, y una suite de automatización de código abierto. Cotiza por WhatsApp.',
    },
    loadComponent: () => import('./pages/home').then((m) => m.Home),
  },
  {
    path: 'portfolio',
    title: `Portafolio | ${SITE_NAME}`,
    // MARKETING-REVIEW: page description
    data: { description: 'Sistemas propios de Hosting3M: ERP hotelero y Agro ERP con asistente de IA.' },
    loadComponent: () => import('./pages/portfolio').then((m) => m.Portfolio),
  },
  {
    path: 'fjpimienta',
    title: `Francisco Jesús Pérez Pimienta | ${SITE_NAME}`,
    // MARKETING-REVIEW: page description
    data: { description: 'Francisco Jesús Pérez Pimienta, ingeniero en Sistemas Computacionales y fundador de Hosting3M en Mérida, Yucatán.' },
    loadComponent: () => import('./pages/profile').then((m) => m.Profile),
  },
  {
    path: 'aviso-de-privacidad',
    title: `Aviso de privacidad | ${SITE_NAME}`,
    // MARKETING-REVIEW: page description
    data: { legal: 'privacy', description: 'Aviso de privacidad de Hosting3M: qué datos recabamos, para qué, con quién los compartimos y cómo ejercer tus derechos ARCO.' },
    loadComponent: () => import('./pages/legal/legal-page').then((m) => m.LegalPage),
  },
  {
    path: 'politica-de-cookies',
    title: `Política de cookies | ${SITE_NAME}`,
    // MARKETING-REVIEW: page description
    data: { legal: 'cookies', description: 'Política de cookies de Hosting3M: qué cookies usa el sitio, para qué y cómo aceptarlas o rechazarlas.' },
    loadComponent: () => import('./pages/legal/legal-page').then((m) => m.LegalPage),
  },
  {
    path: 'terminos-y-condiciones',
    title: `Condiciones de servicio | ${SITE_NAME}`,
    // MARKETING-REVIEW: page description
    data: { legal: 'terms', description: 'Condiciones de servicio de Hosting3M: precios, cobro, renovación, soporte, disponibilidad y responsabilidad.' },
    loadComponent: () => import('./pages/legal/legal-page').then((m) => m.LegalPage),
  },
  {
    // The path /eliminardatosusuarios is referenced by Meta: do not rename it or add a redirect.
    path: 'eliminardatosusuarios',
    title: `Eliminación de datos de usuario | ${SITE_NAME}`,
    // MARKETING-REVIEW: page description
    data: { legal: 'deletion', description: 'Cómo solicitar la cancelación y supresión de tus datos personales en Hosting3M: pasos, plazos, costo y conservación.' },
    loadComponent: () => import('./pages/legal/legal-page').then((m) => m.LegalPage),
  },

  // Renamed legal pages and the old Sitejet URL: nginx answers 301 first (docs/nginx-legacy-redirects.conf); these are the client-side safety net.
  { path: 'politica-de-privacidad', redirectTo: 'aviso-de-privacidad', pathMatch: 'full' },
  { path: 'condiciones-de-servicio', redirectTo: 'terminos-y-condiciones', pathMatch: 'full' },
  { path: 'privacy', redirectTo: 'aviso-de-privacidad' },
  { path: 'news', redirectTo: '' },
  { path: 'noticias-elemento/:post', redirectTo: '' },
  {
    path: '**',
    title: `Página no encontrada | ${SITE_NAME}`,
    data: { description: 'La página que buscas no existe.' },
    loadComponent: () => import('./pages/not-found').then((m) => m.NotFound),
  },
];
