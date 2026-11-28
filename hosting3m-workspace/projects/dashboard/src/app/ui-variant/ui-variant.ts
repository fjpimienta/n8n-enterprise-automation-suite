/**
 * UI variant seam (classic build).
 *
 * The production configuration compiles THIS file. The `demo` configuration replaces it with
 * `ui-variant.next.ts` at build time (angular.json `fileReplacements`), so nothing from the `next`
 * UI or the demo mock is reachable from the production module graph.
 */
import type { HttpInterceptorFn } from '@angular/common/http';
import type { EnvironmentProviders, Provider } from '@angular/core';

export { LoginComponent as LoginPageComponent } from '../features/admin/components/login/login.component';
export { DashboardComponent as HomePageComponent } from '../features/dashboard/components/dashboard/dashboard.component';
export { MainLayoutComponent as ShellLayoutComponent } from '../shared/ui/layout/main-layout/main-layout.component';

export const UI_MODE: 'classic' | 'next' = 'classic';

/** Extra HTTP interceptors (none in classic). */
export const uiHttpInterceptors: HttpInterceptorFn[] = [];

/** Extra application providers (none in classic). */
export const uiProviders: (Provider | EnvironmentProviders)[] = [];
