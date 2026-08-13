import { ApplicationConfig, provideZonelessChangeDetection } from '@angular/core';
import { provideRouter } from '@angular/router';
import { provideHttpClient, withInterceptors } from '@angular/common/http';

import { routes } from './app.routes';
import { environment } from '@env/environment';
import { AiService, CHAT_CONFIG_TOKEN } from 'ui-chat';

// 🚀 IMPORTS ESTRICTOS DE LA LIBRERÍA
import { AUTH_ENV_CONFIG, authInterceptor } from 'core-auth';

export const appConfig: ApplicationConfig = {
  providers: [
    provideZonelessChangeDetection(),
    provideRouter(routes),
    provideHttpClient(withInterceptors([authInterceptor])),

    // 🚀 INYECCIÓN DE CONTEXTO MULTI-TENANT
    {
      provide: AUTH_ENV_CONFIG,
      useValue: {
        apiUrl_crud: environment.apiUrl_crud,
        apiUrl_token: environment.apiUrl_token,
        system_id: 'hotel_dashboard',
        apiUrl_upload: environment.apiUrl_upload
      }
    },

    AiService,
    {
      provide: CHAT_CONFIG_TOKEN,
      useValue: {
        apiUrl_ai: environment.apiUrl_ai,
        logoUrl: 'assets/images/logo_hotel_san_jose.png',
        title: 'Asistente Hotel San José',
        primaryColor: '#6c9a40'
      }
    }
  ]
};