import { DOCUMENT } from '@angular/common';
import { Injectable, PLATFORM_ID, inject, signal } from '@angular/core';
import { isPlatformBrowser } from '@angular/common';
import { Router, NavigationEnd } from '@angular/router';
import { filter } from 'rxjs';
import { SITE } from './site.config';

const STORAGE_KEY = 'h3m_cookie_consent_v1';

type Choice = 'granted' | 'denied';
type GtagWindow = Window & { dataLayer?: unknown[]; gtag?: (...args: unknown[]) => void; [key: string]: unknown };

/** Cookie consent. GA4 is never loaded before the visitor accepts analytics. */
@Injectable({ providedIn: 'root' })
export class ConsentService {
  private readonly document = inject(DOCUMENT);
  private readonly router = inject(Router);
  private readonly isBrowser = isPlatformBrowser(inject(PLATFORM_ID));
  private gaLoaded = false;

  readonly choice = signal<Choice | null>(null);
  readonly bannerOpen = signal(false);

  init(): void {
    if (!this.isBrowser) return;
    const saved = this.read();
    this.choice.set(saved);
    this.bannerOpen.set(saved === null);
    if (saved === 'granted') this.loadAnalytics();
    this.router.events
      .pipe(filter((e): e is NavigationEnd => e instanceof NavigationEnd))
      .subscribe((e) => this.pageView(e.urlAfterRedirects));
  }

  accept(): void {
    this.save('granted');
    this.loadAnalytics();
  }

  reject(): void {
    this.save('denied');
    this.disableAnalytics();
  }

  reopen(): void {
    this.bannerOpen.set(true);
  }

  private read(): Choice | null {
    try {
      const value = localStorage.getItem(STORAGE_KEY);
      return value === 'granted' || value === 'denied' ? value : null;
    } catch {
      return null;
    }
  }

  private save(choice: Choice): void {
    try {
      localStorage.setItem(STORAGE_KEY, choice);
    } catch {
      /* storage unavailable: keep the choice for this page view only */
    }
    this.choice.set(choice);
    this.bannerOpen.set(false);
  }

  private win(): GtagWindow {
    return this.document.defaultView as unknown as GtagWindow;
  }

  private loadAnalytics(): void {
    const w = this.win();
    w[`ga-disable-${SITE.ga4Id}`] = false;
    if (this.gaLoaded) return;
    this.gaLoaded = true;
    w.dataLayer = w.dataLayer ?? [];
    w.gtag = function () {
      // gtag requires the real `arguments` object, not an array.
      // eslint-disable-next-line prefer-rest-params
      w.dataLayer!.push(arguments);
    };
    w.gtag('consent', 'default', { analytics_storage: 'granted', ad_storage: 'denied', ad_user_data: 'denied', ad_personalization: 'denied' });
    w.gtag('js', new Date());
    w.gtag('config', SITE.ga4Id, { anonymize_ip: true, send_page_view: false });
    const script = this.document.createElement('script');
    script.async = true;
    script.src = `https://www.googletagmanager.com/gtag/js?id=${encodeURIComponent(SITE.ga4Id)}`;
    this.document.head.appendChild(script);
    this.pageView(this.router.url);
  }

  private disableAnalytics(): void {
    const w = this.win();
    w[`ga-disable-${SITE.ga4Id}`] = true;
    w.gtag?.('consent', 'update', { analytics_storage: 'denied' });
  }

  private pageView(url: string): void {
    const w = this.win();
    if (this.choice() !== 'granted' || !w.gtag) return;
    w.gtag('event', 'page_view', { page_path: url.split('#')[0], page_location: this.document.location.href });
  }
}
