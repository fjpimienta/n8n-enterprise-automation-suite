import { ApplicationConfig, importProvidersFrom } from '@angular/core';
import { provideRouter } from '@angular/router';
import { routes } from './app.routes';
// 1. IMPORTANTE: Agregar 'withInterceptors' aquí
import { provideHttpClient, withFetch, withInterceptors } from '@angular/common/http';

// 2. IMPORTANTE: Importar tu interceptor (ajusta la ruta si es diferente, usé la de tu versión anterior)
import { authInterceptor } from '@core/auth/auth-interceptor';

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