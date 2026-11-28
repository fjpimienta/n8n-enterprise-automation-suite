/**
 * UI variant seam (demo build). Replaces `ui-variant.ts` only in the `demo` configuration.
 * Registers the synthetic-data mock; it never forwards a request to the network.
 */
import type { HttpInterceptorFn } from '@angular/common/http';
import type { Provider } from '@angular/core';
import { demoMockInterceptor } from '../demo/demo-mock.interceptor';

export { LoginComponent as LoginPageComponent } from '../features/admin/components/login/login.component';
export { DashboardComponent as HomePageComponent } from '../features/dashboard/components/dashboard/dashboard.component';
export { MainLayoutComponent as ShellLayoutComponent } from '../shared/ui/layout/main-layout/main-layout.component';

export const UI_MODE: 'classic' | 'next' = 'next';

export const uiHttpInterceptors: HttpInterceptorFn[] = [demoMockInterceptor];

export const uiProviders: Provider[] = [];
