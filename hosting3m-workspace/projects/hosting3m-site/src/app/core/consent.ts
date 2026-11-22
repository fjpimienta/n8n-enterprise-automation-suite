import { DOCUMENT } from '@angular/common';
import { Injectable, PLATFORM_ID, inject, signal } from '@angular/core';
import { isPlatformBrowser } from '@angular/common';
import { Router, NavigationEnd } from '@angular/router';
import { filter } from 'rxjs';
import { SITE } from './site.config';

export const STORAGE_KEY = 'h3m_cookie_consent_v1';

type Choice = 'granted' | 'denied';
type GtagWindow = Window & { dataLayer?: unknown[]; gtag?: (...args: unknown[]) => void; [key: string]: unknown };

/** Cookie consent. GA4 is never loaded before the visitor accepts analytics. */
@Injectable({ providedIn: 'root' })
export class ConsentService {
  private readonly document = inject(DOCUMENT);
  private readonly router = inject(Router);
  private readonly isBrowser = isPlatformBrowser(inject(PLATFORM_ID));
  private gaLoaded = false;
  /** Used when localStorage is unavailable (private mode, blocked storage): the choice lasts for this visit only. */
  private memoryChoice: Choice | null = null;

  readonly choice = signal<Choice | null>(null);
  readonly bannerOpen = signal(false);
  /** Increments each time the banner is reopened on purpose, so it can take focus (not on first load). */
  readonly reopenCount = signal(0);

  init(): void {
    if (!this.isBrowser) return;
    const saved = this.read();
    this.choice.set(saved);
    this.bannerOpen.set(saved === null);
    this.setupConsentMode(); // Consent Mode v2 default: everything denied. No script, no cookies yet.
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
    this.reopenCount.update((n) => n + 1);
  }

  private read(): Choice | null {
    try {
      const value = localStorage.getItem(STORAGE_KEY);
      return value === 'granted' || value === 'denied' ? value : this.memoryChoice;
    } catch {
      return this.memoryChoice;
    }
  }

  private save(choice: Choice): void {
    this.memoryChoice = choice;
    try {
      localStorage.setItem(STORAGE_KEY, choice);
    } catch {
      /* storage unavailable: the in-memory choice above is used for this visit */
    }
    this.choice.set(choice);
    this.bannerOpen.set(false);
  }

  private win(): GtagWindow {
    return this.document.defaultView as unknown as GtagWindow;
  }

  /** Defines gtag and sends the Consent Mode v2 defaults (all denied). Loads nothing from the network. */
  private setupConsentMode(): void {
    const w = this.win();
    if (w.gtag) return;
    w.dataLayer = w.dataLayer ?? [];
    w.gtag = function () {
      // gtag requires the real `arguments` object, not an array.
      // eslint-disable-next-line prefer-rest-params
      w.dataLayer!.push(arguments);
    };
    w.gtag('consent', 'default', { analytics_storage: 'denied', ad_storage: 'denied', ad_user_data: 'denied', ad_personalization: 'denied' });
  }

  private loadAnalytics(): void {
    const w = this.win();
    this.setupConsentMode();
    w[`ga-disable-${SITE.ga4Id}`] = false;
    // Only analytics is granted; the advertising signals stay denied.
    w.gtag!('consent', 'update', { analytics_storage: 'granted' });
    if (this.gaLoaded) return;
    this.gaLoaded = true;
    w.gtag!('js', new Date());
    w.gtag!('config', SITE.ga4Id, { anonymize_ip: true, send_page_view: false });
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
    this.clearAnalyticsCookies();
  }

  /** Withdrawing consent also removes the first-party GA cookies set earlier (_ga, _ga_<id>, _gid, _gat*). */
  private clearAnalyticsCookies(): void {
    const names = this.document.cookie
      .split(';')
      .map((c) => c.split('=')[0].trim())
      .filter((n) => n === '_ga' || n === '_gid' || n.startsWith('_ga_') || n.startsWith('_gat'));
    const host = this.document.location.hostname;
    const parts = host.split('.');
    const domains = ['', host, ...(parts.length > 2 ? [`.${parts.slice(-2).join('.')}`] : [`.${host}`])];
    for (const name of names) {
      for (const domain of domains) {
        this.document.cookie = `${name}=; expires=Thu, 01 Jan 1970 00:00:00 GMT; path=/${domain ? `; domain=${domain}` : ''}`;
      }
    }
  }

  private pageView(url: string): void {
    const w = this.win();
    if (this.choice() !== 'granted' || !w.gtag) return;
    w.gtag('event', 'page_view', { page_path: url.split('#')[0], page_location: this.document.location.href });
  }
}
