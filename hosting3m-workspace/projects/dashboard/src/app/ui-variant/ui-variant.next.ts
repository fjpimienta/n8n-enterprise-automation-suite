/**
 * UI variant seam (demo build). Replaces `ui-variant.ts` only in the `demo` configuration.
 * Registers the synthetic-data mock; it never forwards a request to the network.
 */
import type { HttpInterceptorFn } from '@angular/common/http';
import { provideAppInitializer, type EnvironmentProviders, type Provider } from '@angular/core';
import { demoMockInterceptor } from '../demo/demo-mock.interceptor';

export { LoginNextComponent as LoginPageComponent } from '../next/login/login-next.component';
export { HomeNextComponent as HomePageComponent } from '../next/home/home-next.component';
export { ShellLayoutNextComponent as ShellLayoutComponent } from '../next/shell/shell-layout-next.component';

export const UI_MODE: 'classic' | 'next' = 'next';

export const uiHttpInterceptors: HttpInterceptorFn[] = [demoMockInterceptor];

/** Activates the `theme-hotel` scope; every `next` style is gated on this class. */
export const uiProviders: (Provider | EnvironmentProviders)[] = [
  provideAppInitializer(() => { document.body.classList.add('theme-hotel'); })
];
