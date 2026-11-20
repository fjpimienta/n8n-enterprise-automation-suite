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
    loadComponent: () => import('./pages/home').then((m) => m.Home),
  },
  {
    path: 'portfolio',
    title: `Portafolio | ${SITE_NAME}`,
    loadComponent: () => import('./pages/placeholder').then((m) => m.Placeholder),
    data: { heading: 'Portafolio', todo: 'TODO_PORTFOLIO: casos reales por aprobar' },
  },
  {
    path: 'fjpimienta',
    title: `Francisco Pérez Pimienta | ${SITE_NAME}`,
    loadComponent: () => import('./pages/placeholder').then((m) => m.Placeholder),
    data: { heading: 'Francisco Pérez Pimienta', todo: 'TODO_PROFILE: contenido por aprobar' },
  },
  {
    path: 'politica-de-privacidad',
    title: `Política de privacidad | ${SITE_NAME}`,
    loadComponent: () => import('./pages/placeholder').then((m) => m.Placeholder),
    data: { heading: 'Política de privacidad', todo: 'Texto legal se migra en la fase 2' },
  },
  {
    path: 'condiciones-de-servicio',
    title: `Condiciones de servicio | ${SITE_NAME}`,
    loadComponent: () => import('./pages/placeholder').then((m) => m.Placeholder),
    data: { heading: 'Condiciones de servicio', todo: 'Texto legal se migra en la fase 2; TODO_LEGAL_ENTITY' },
  },
  {
    path: 'eliminardatosusuarios',
    title: `Eliminación de datos de usuario | ${SITE_NAME}`,
    loadComponent: () => import('./pages/placeholder').then((m) => m.Placeholder),
    data: { heading: 'Eliminación de datos de usuario', todo: 'Texto legal se migra en la fase 2 (URL exigida por Meta)' },
  },
  { path: 'privacy', redirectTo: 'politica-de-privacidad' },
  { path: 'news', redirectTo: '' },
  { path: 'noticias-elemento/:post', redirectTo: '' },
  {
    path: '**',
    title: `Página no encontrada | ${SITE_NAME}`,
    loadComponent: () => import('./pages/not-found').then((m) => m.NotFound),
  },
];
