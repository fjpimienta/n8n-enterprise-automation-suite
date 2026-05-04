import { ApplicationConfig, importProvidersFrom, provideBrowserGlobalErrorListeners } from '@angular/core';
import { provideRouter } from '@angular/router';
import { provideHttpClient, withFetch, withInterceptors } from '@angular/common/http';
import { routes } from './app.routes';
// import { environment } from '@env/environment';

// Integración de Librería Compartida
import { CHAT_CONFIG_TOKEN, AiService } from 'ui-chat';

// Seguridad y Núcleo
// import { authInterceptor } from '@core/auth/auth-interceptor';

// UI Icons (Optimización Tree-shaking)
import {
  LucideAngularModule,
  ChevronsLeft, ChevronsRight, X, Sun, Moon,
  Monitor, FileText, Users, LogOut, Plus, Briefcase,
  Banknote, CreditCard, Check, RefreshCw, Activity, Map
} from 'lucide-angular';

export const appConfig: ApplicationConfig = {
  providers: [
    provideRouter(routes),
    provideBrowserGlobalErrorListeners(), // Mantenido según tu base[cite: 8]

    // 1. Configuración de Cliente HTTP con Resiliencia y Seguridad[cite: 7]
    provideHttpClient(
      withFetch()//,
      //withInterceptors([authInterceptor]) // Inyección del Token JWT para Webhooks n8n[cite: 7]
    ),

    // 2. Provisión de Servicios de IA[cite: 7]
    AiService,
    {
      provide: CHAT_CONFIG_TOKEN,
      useValue: {
        apiUrl_ai: 'http://localhost:5678/webhook/v3/ai/chat-pista', // environment.apiUrl_ai,
        title: 'Asistente Ganadería Digital',
        logoUrl: 'assets/images/logo_cattle.png', // Logo específico del proyecto
        primaryColor: '#2d6a4f' // Verde agro-industrial
      }
    },

    // 3. Registro de Iconografía Reutilizable[cite: 7]
    importProvidersFrom(LucideAngularModule.pick({
      ChevronsLeft, ChevronsRight, X, Sun, Moon,
      Monitor, FileText, Users, LogOut, Plus, Briefcase,
      Banknote, CreditCard, Check, RefreshCw, Activity, Map
    }))
  ]
};