import { ApplicationConfig, provideZonelessChangeDetection } from '@angular/core';
import { provideRouter } from '@angular/router';
import { provideHttpClient, withInterceptors } from '@angular/common/http';

import { routes } from './app.routes';
import { authInterceptor } from './core/auth/auth.interceptor';
import { AiService, CHAT_CONFIG_TOKEN } from 'ui-chat';
import { environment } from '@env/environment';

export const appConfig: ApplicationConfig = {
  providers: [
    provideZonelessChangeDetection(),
    provideRouter(routes),
    provideHttpClient(withInterceptors([authInterceptor])),
    AiService,
    {
      provide: CHAT_CONFIG_TOKEN,
      useValue: {
        apiUrl_ai: environment.apiUrl_ai,
        logoUrl: 'assets/images/logo_cattle.png',
        title: 'Asistente Gestión Ganadera',
        primaryColor: '#6c9a40'
      }
    }
  ]
};