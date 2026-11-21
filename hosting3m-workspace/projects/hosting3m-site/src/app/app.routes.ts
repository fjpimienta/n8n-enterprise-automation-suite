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
    path: 'politica-de-privacidad',
    title: `Política de privacidad | ${SITE_NAME}`,
    data: { description: 'Cómo Hosting3M recopila, usa y protege tus datos personales.' },
    loadComponent: () => import('./pages/legal/privacy').then((m) => m.Privacy),
  },
  {
    path: 'condiciones-de-servicio',
    title: `Condiciones de servicio | ${SITE_NAME}`,
    data: { description: 'Condiciones de servicio de Hosting3M.' },
    loadComponent: () => import('./pages/legal/terms').then((m) => m.Terms),
  },
  {
    path: 'eliminardatosusuarios',
    title: `Eliminación de datos de usuario | ${SITE_NAME}`,
    data: { description: 'Cómo solicitar la eliminación de tus datos de usuario en Hosting3M.' },
    loadComponent: () => import('./pages/legal/deletion').then((m) => m.Deletion),
  },
  { path: 'privacy', redirectTo: 'politica-de-privacidad' },
  { path: 'news', redirectTo: '' },
  { path: 'noticias-elemento/:post', redirectTo: '' },
  {
    path: '**',
    title: `Página no encontrada | ${SITE_NAME}`,
    data: { description: 'La página que buscas no existe.' },
    loadComponent: () => import('./pages/not-found').then((m) => m.NotFound),
  },
];
