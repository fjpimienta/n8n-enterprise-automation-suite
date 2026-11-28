/**
 * UI variant seam (demo build). Replaces `ui-variant.ts` only in the `demo` configuration.
 * Registers the synthetic-data mock; it never forwards a request to the network.
 */
import type { HttpInterceptorFn } from '@angular/common/http';
import { provideAppInitializer, type EnvironmentProviders, type Provider } from '@angular/core';
import type { Routes } from '@angular/router';
import { demoMockInterceptor } from '../demo/demo-mock.interceptor';
import { HousekeepingNextComponent } from '../next/housekeeping/housekeeping-next.component';
import { MaintenanceNextComponent } from '../next/maintenance/maintenance-next.component';

export { LoginNextComponent as LoginPageComponent } from '../next/login/login-next.component';
export { HomeNextComponent as HomePageComponent } from '../next/home/home-next.component';
export { ShellLayoutNextComponent as ShellLayoutComponent } from '../next/shell/shell-layout-next.component';

export const UI_MODE: 'classic' | 'next' = 'next';

export const uiHttpInterceptors: HttpInterceptorFn[] = [demoMockInterceptor];

/**
 * Child routes that exist only in the `next` UI. They are listed BEFORE the classic children in `app.routes.ts`, so
 * `mantenimiento` here replaces the classic monitor page in `next` (in classic this list is empty).
 */
export const uiChildRoutes: Routes = [
  { path: 'limpieza', component: HousekeepingNextComponent },
  { path: 'mantenimiento', component: MaintenanceNextComponent }
];

/** Activates the `theme-hotel` scope; every `next` style is gated on this class. */
export const uiProviders: (Provider | EnvironmentProviders)[] = [
  provideAppInitializer(() => { document.body.classList.add('theme-hotel'); })
];
