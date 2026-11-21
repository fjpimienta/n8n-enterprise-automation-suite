import { Component } from '@angular/core';
import { TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { ConsentService } from './consent';
import { CookieBanner } from '../sections/cookie-banner';
import { Footer } from '../layout/footer';
import { SITE } from './site.config';

type W = Window & { dataLayer?: unknown[]; gtag?: unknown; [k: string]: unknown };
const KEY = 'h3m_cookie_consent_v1';
const win = () => window as unknown as W;
const gaScripts = () => document.head.querySelectorAll('script[src*="googletagmanager.com"]');
const consentCalls = () => (win().dataLayer ?? []).map((e) => Array.from(e as ArrayLike<unknown>)).filter((a) => a[0] === 'consent');

function setup() {
  TestBed.configureTestingModule({ providers: [provideRouter([])] });
  return TestBed.inject(ConsentService);
}

beforeEach(() => {
  localStorage.clear();
  delete win().dataLayer;
  delete win().gtag;
  gaScripts().forEach((s) => s.remove());
});
afterEach(() => vi.restoreAllMocks());

describe('ConsentService', () => {
  it('defaults to denied (Consent Mode v2), shows the banner and loads nothing', () => {
    const consent = setup();
    consent.init();
    expect(consent.choice()).toBeNull();
    expect(consent.bannerOpen()).toBe(true);
    expect(consentCalls()[0]).toEqual(['consent', 'default', { analytics_storage: 'denied', ad_storage: 'denied', ad_user_data: 'denied', ad_personalization: 'denied' }]);
    expect(gaScripts()).toHaveLength(0);
  });

  it('accept loads analytics and grants only analytics_storage', () => {
    const consent = setup();
    consent.init();
    consent.accept();
    expect(gaScripts()).toHaveLength(1);
    expect((gaScripts()[0] as HTMLScriptElement).src).toContain(SITE.ga4Id);
    expect(consentCalls()[1]).toEqual(['consent', 'update', { analytics_storage: 'granted' }]);
    expect(consent.bannerOpen()).toBe(false);
    consent.accept();
    expect(gaScripts()).toHaveLength(1); // never loaded twice
  });

  it('reject never loads analytics', () => {
    const consent = setup();
    consent.init();
    consent.reject();
    expect(gaScripts()).toHaveLength(0);
    expect(consent.choice()).toBe('denied');
    expect(consentCalls().some((c) => (c[2] as Record<string, string>)['analytics_storage'] === 'granted')).toBe(false);
  });

  it('persists the choice and applies it on the next visit', () => {
    setup().init();
    TestBed.inject(ConsentService).accept();
    expect(localStorage.getItem(KEY)).toBe('granted');

    TestBed.resetTestingModule();
    delete win().gtag;
    delete win().dataLayer;
    gaScripts().forEach((s) => s.remove());
    const next = setup();
    next.init();
    expect(next.choice()).toBe('granted');
    expect(next.bannerOpen()).toBe(false);
    expect(gaScripts()).toHaveLength(1);
  });

  it('keeps the choice in memory when localStorage throws', () => {
    vi.spyOn(Storage.prototype, 'setItem').mockImplementation(() => {
      throw new Error('blocked');
    });
    vi.spyOn(Storage.prototype, 'getItem').mockImplementation(() => {
      throw new Error('blocked');
    });
    const consent = setup();
    consent.init();
    expect(() => consent.reject()).not.toThrow();
    expect(consent.choice()).toBe('denied');
    expect(gaScripts()).toHaveLength(0);
  });
});

@Component({ imports: [CookieBanner, Footer], template: '<app-cookie-banner /><app-footer />' })
class Host {}

describe('cookie banner and footer link', () => {
  it('shows two equal buttons and a privacy link, and the footer link reopens it after a choice', async () => {
    TestBed.configureTestingModule({ providers: [provideRouter([])] });
    const consent = TestBed.inject(ConsentService);
    consent.init();
    const fixture = TestBed.createComponent(Host);
    fixture.detectChanges();
    const el = fixture.nativeElement as HTMLElement;
    const buttons = Array.from(el.querySelectorAll<HTMLButtonElement>('section[aria-label="Preferencias de cookies"] button'));
    expect(buttons.map((b) => b.textContent?.trim())).toEqual(['Rechazar', 'Aceptar']);
    expect(buttons[0].className).toBe(buttons[1].className);
    expect(el.querySelector('section[aria-label="Preferencias de cookies"] a[href="/politica-de-privacidad"]')).not.toBeNull();

    buttons[0].click();
    fixture.detectChanges();
    expect(el.querySelector('section[aria-label="Preferencias de cookies"]')).toBeNull();

    const link = Array.from(el.querySelectorAll<HTMLButtonElement>('footer button')).find((b) => b.textContent?.includes('Preferencias de cookies'))!;
    link.click();
    fixture.detectChanges();
    const banner = el.querySelector<HTMLElement>('section[aria-label="Preferencias de cookies"]');
    expect(banner).not.toBeNull();
    await new Promise((r) => setTimeout(r));
    expect(document.activeElement).toBe(banner);
  });
});
