import { ApplicationConfig, importProvidersFrom, provideBrowserGlobalErrorListeners } from '@angular/core';
import { provideRouter } from '@angular/router';
import { routes } from './app.routes';
import { provideClientHydration, withEventReplay } from '@angular/platform-browser';
import { provideHttpClient, withFetch, withInterceptors } from '@angular/common/http';
import { RefreshCw, Snowflake } from 'lucide-angular';
import { authInterceptor } from '@core/auth/auth-interceptor';
import {
  LucideAngularModule,
  ChevronsLeft, ChevronsRight, X, Sun, Moon,
  Monitor, FileText, Users, LogOut, Plus, Briefcase,
  Banknote, CreditCard, Check
} from 'lucide-angular';
export const appConfig: ApplicationConfig = {
  providers: [
    provideBrowserGlobalErrorListeners(),
    provideRouter(routes),
    provideClientHydration(withEventReplay()),
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
      Check
    }))
  ]
};