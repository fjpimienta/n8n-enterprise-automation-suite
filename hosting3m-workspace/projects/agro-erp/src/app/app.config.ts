import { ApplicationConfig, isDevMode, provideAppInitializer, provideZonelessChangeDetection } from '@angular/core';
import { provideRouter } from '@angular/router';
import { provideHttpClient, withInterceptors } from '@angular/common/http';
import { provideServiceWorker } from '@angular/service-worker';

import { routes } from './app.routes';
import { environment } from '@env/environment';
import { purgeLegacySwCaches } from '@core/utils/legacy-sw-cache.util';
import { wireOfflineLogoutWipe } from '@core/utils/offline-logout-wipe.util';
import { wirePinLogoutWipe } from '@core/utils/pin-logout-wipe.util';
import { startOfflineSessionWatch } from '@core/utils/offline-session-watch.util';
import { offlineGraceGuard } from '@core/interceptors/offline-grace.interceptor';
import { graceAuthInterceptor } from '@core/interceptors/grace-auth.interceptor';
import { AUTH_ENV_CONFIG, tenantInterceptor } from 'core-auth';

// ✅ 1. Importar el Token y el Servicio desde la librería ui-chat
import { AiService, CHAT_CONFIG_TOKEN } from 'ui-chat';

export const appConfig: ApplicationConfig = {
  providers: [
    provideZonelessChangeDetection(),
    provideRouter(routes),
    provideHttpClient(withInterceptors([offlineGraceGuard, graceAuthInterceptor, tenantInterceptor])),

    // PWA app shell (Refs #1087): Angular's service worker, production builds only. It caches the
    // app shell and chunks; it does NOT cache gateway data (offline data is phase 1b).
    provideServiceWorker('ngsw-worker.js', {
      enabled: !isDevMode(),
      registrationStrategy: 'registerWhenStable:30000',
    }),
    // Drop the cache of the retired hand-written worker (see public/sw.js).
    provideAppInitializer(() => {
      void purgeLegacySwCaches();
    }),
    // Wipe the offline read cache when the session ends (Refs #1087).
    provideAppInitializer(() => wireOfflineLogoutWipe()),
    // PIN records are deleted on logout too (separate database, #1087 phase 1b-iii-b).
    provideAppInitializer(() => wirePinLogoutWipe()),
    // Re-checks the session (no HTTP) so an open app re-locks when it enters grace.
    provideAppInitializer(() => startOfflineSessionWatch()),

    // Configuración de la librería core-auth
    {
      provide: AUTH_ENV_CONFIG,
      useValue: {
        apiUrl_crud: environment.apiUrl_crud,
        apiUrl_token: environment.apiUrl_token,
        apiUrl_ai: environment.apiUrl_ai,
        apiUrl_upload: environment.apiUrl_upload
      }
    },

    // 🚀 2. Registrar el Servicio y Proveer el Token para ui-chat
    AiService,
    {
      provide: CHAT_CONFIG_TOKEN,
      useValue: {
        apiUrl_ai: environment.apiUrl_ai, // Asegúrate que esta variable exista en environment.ts
        logoUrl: 'assets/images/logo_agroerp.png',
        title: 'Asistente IA - Agro ERP',
        primaryColor: '#6c9a40', // Verde para el AGRO ERP
        attachments: { enabled: true } // CFDI invoice upload; set to false to disable
      }
    }
  ]
};