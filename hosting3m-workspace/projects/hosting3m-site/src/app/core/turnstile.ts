import { DOCUMENT, isPlatformBrowser } from '@angular/common';
import { Injectable, PLATFORM_ID, inject } from '@angular/core';
import { RUNTIME } from './runtime-config';

interface TurnstileApi {
  render(el: HTMLElement, options: Record<string, unknown>): string;
  reset(widgetId: string): void;
  remove(widgetId: string): void;
}
type TurnstileWindow = Window & { turnstile?: TurnstileApi };

const SCRIPT_URL = 'https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit';

export interface TurnstileCallbacks {
  onToken(token: string): void;
  onClear(): void;
}

@Injectable({ providedIn: 'root' })
export class TurnstileService {
  private readonly document = inject(DOCUMENT);
  private readonly isBrowser = isPlatformBrowser(inject(PLATFORM_ID));
  private scriptPromise: Promise<TurnstileApi> | null = null;

  /** Renders the widget and returns a handle, or null on the server. In mock mode no network is used. */
  async render(el: HTMLElement, cb: TurnstileCallbacks): Promise<{ reset(): void; remove(): void } | null> {
    if (!this.isBrowser) return null;
    if (RUNTIME.mockApi) {
      cb.onToken('dev-mock-token');
      return { reset: () => cb.onToken('dev-mock-token'), remove: () => undefined };
    }
    const api = await this.load();
    const id = api.render(el, {
      sitekey: RUNTIME.turnstileSiteKey,
      language: 'es',
      callback: (token: string) => cb.onToken(token),
      'expired-callback': () => cb.onClear(),
      'error-callback': () => cb.onClear(),
    });
    return {
      reset: () => {
        cb.onClear();
        api.reset(id);
      },
      remove: () => api.remove(id),
    };
  }

  private load(): Promise<TurnstileApi> {
    this.scriptPromise ??= new Promise<TurnstileApi>((resolve, reject) => {
      const w = this.document.defaultView as unknown as TurnstileWindow;
      if (w.turnstile) return resolve(w.turnstile);
      const script = this.document.createElement('script');
      script.src = SCRIPT_URL;
      script.async = true;
      script.onload = () => (w.turnstile ? resolve(w.turnstile) : reject(new Error('turnstile unavailable')));
      script.onerror = () => {
        this.scriptPromise = null;
        reject(new Error('turnstile failed to load'));
      };
      this.document.head.appendChild(script);
    });
    return this.scriptPromise;
  }
}
