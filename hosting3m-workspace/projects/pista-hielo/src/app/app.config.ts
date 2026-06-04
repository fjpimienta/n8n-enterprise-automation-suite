import { ApplicationConfig, importProvidersFrom } from '@angular/core';
import { provideRouter } from '@angular/router';
import { routes } from './app.routes';
import { CHAT_CONFIG_TOKEN, AiService } from 'ui-chat';
// 1. IMPORTANTE: Agregar 'withInterceptors' aquí
import { provideHttpClient, withFetch, withInterceptors } from '@angular/common/http';
// 🟢 AGREGAR ESTAS IMPORTACIONES DE TU LIBRERÍA:

// 2. IMPORTANTE: Importar tu interceptor (ajusta la ruta si es diferente, usé la de tu versión anterior)
import { authInterceptor, AUTH_ENV_CONFIG } from 'core-auth';
import { environment } from '@env/environment';

import {
  LucideAngularModule,
  ChevronsLeft, ChevronsRight, X, Sun, Moon,
  Monitor, FileText, Users, LogOut, Plus, Briefcase,
  Banknote, CreditCard, Check,
  RefreshCw
} from 'lucide-angular';

export const appConfig: ApplicationConfig = {
  providers: [
    provideRouter(routes),

    // 3. AQUÍ ESTABA EL ERROR: Se agrega withInterceptors para activar el token
    provideHttpClient(
      withFetch(),
      withInterceptors([authInterceptor])
    ),
    // 👇 NUEVO: Le pasamos la configuración a la librería de Auth
    {
      provide: AUTH_ENV_CONFIG,
      useValue: {
        apiUrl_crud: environment.apiUrl_crud,
        apiUrl_token: environment.apiUrl_token,
        system_id: environment.system_id
      }
    },
    AiService,
    {
      provide: CHAT_CONFIG_TOKEN,
      useValue: {
        apiUrl_ai: environment.apiUrl_ai,
        title: 'Asistente Pista Hielo',
        logoUrl: 'assets/images/logo_pista.png',
        primaryColor: '#00d2ff'
      }
    },
    importProvidersFrom(LucideAngularModule.pick({
      ChevronsLeft,
      ChevronsRight,
      X,
      Sun,
      Moon,
      Monitor,
      FileText,
      Users,
      LogOut,
      Plus,
      Briefcase,
      Banknote,
      CreditCard,
      Check,
      RefreshCw
    }))
  ]
};