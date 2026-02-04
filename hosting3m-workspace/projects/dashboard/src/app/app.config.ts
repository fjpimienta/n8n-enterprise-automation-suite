import { ApplicationConfig, provideZonelessChangeDetection } from '@angular/core'; // <--- Nombre actualizado
import { provideRouter } from '@angular/router';
import { provideHttpClient, withInterceptors } from '@angular/common/http';

import { routes } from './app.routes';
import { authInterceptor } from './core/auth/auth.interceptor';
import { CHAT_CONFIG } from 'ui-chat';
import { environment } from '@env/environment';

export const appConfig: ApplicationConfig = {
  providers: [
    provideZonelessChangeDetection(), // <--- Sin la palabra "Experimental"
    provideRouter(routes),
    provideHttpClient(withInterceptors([authInterceptor])),
    { provide: CHAT_CONFIG, useValue: { apiUrl_ai: environment.apiUrl_ai } }
  ]
};