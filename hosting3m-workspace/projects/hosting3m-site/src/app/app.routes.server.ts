import { RenderMode, ServerRoute } from '@angular/ssr';

/**
 * Every route is prerendered at build time (static output, no Node server in production).
 * The parameterized legacy redirect is handled by nginx (301), so it is not prerendered.
 */
export const serverRoutes: ServerRoute[] = [
  { path: 'noticias-elemento/:post', renderMode: RenderMode.Client },
  { path: '**', renderMode: RenderMode.Prerender },
];
