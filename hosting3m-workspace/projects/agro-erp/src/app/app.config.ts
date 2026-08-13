import { ApplicationConfig, provideZonelessChangeDetection } from '@angular/core';
import { provideRouter } from '@angular/router';
import { provideHttpClient, withInterceptors } from '@angular/common/http';

import { routes } from './app.routes';
import { environment } from '@env/environment';
import { AUTH_ENV_CONFIG, authInterceptor, tenantInterceptor } from 'core-auth';

// ✅ 1. Importar el Token y el Servicio desde la librería ui-chat
import { AiService, CHAT_CONFIG_TOKEN } from 'ui-chat';

export const appConfig: ApplicationConfig = {
  providers: [
    provideZonelessChangeDetection(),
    provideRouter(routes),
    provideHttpClient(withInterceptors([authInterceptor, tenantInterceptor])),

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
        primaryColor: '#6c9a40' // Verde para el AGRO ERP
      }
    }
  ]
};