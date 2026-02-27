import { ApplicationConfig, provideBrowserGlobalErrorListeners } from '@angular/core';
import { provideRouter } from '@angular/router';
import { provideHttpClient } from '@angular/common/http';
import { routes } from './app.routes';
import { CHAT_CONFIG_TOKEN, AiService } from 'ui-chat';
import { environment } from '../environments/environment.prod';

export const appConfig: ApplicationConfig = {
  providers: [
    provideBrowserGlobalErrorListeners(),
    provideRouter(routes),
    provideHttpClient(),
    AiService,
    {
      provide: CHAT_CONFIG_TOKEN,
      useValue: {
        apiUrl_ai: environment.apiUrl_ai,
        logoUrl: 'images/logo_hotel_san_jose.png',
        title: 'Asistente Hotel San José',
        primaryColor: '#6c9a40'
      }
    }
  ]
};