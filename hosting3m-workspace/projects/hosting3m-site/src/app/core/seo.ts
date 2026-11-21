import { DOCUMENT } from '@angular/common';
import { Injectable, inject } from '@angular/core';
import { Meta, Title } from '@angular/platform-browser';
import { ActivatedRouteSnapshot, NavigationEnd, Router } from '@angular/router';
import { filter } from 'rxjs';
import { BUSINESS } from './business';
import { SITE } from './site.config';
import { CONTACT_SERVICES } from './contact';

const JSON_LD_ID = 'jsonld-site';

/** Social preview (1200x630 JPG: crawlers do not all support WebP/AVIF). */
export const OG_IMAGE = {
  url: `${SITE.url}/images/og-image.jpg`,
  width: 1200,
  height: 630,
  alt: 'Logotipo de Hosting3M junto a una persona trabajando con una laptop bajo una nube con íconos de servidores, inteligencia artificial y sitios web',
} as const;

/** schema.org graph for the home page. Only verified facts (see core/business.ts): no ratings or prices. */
export function buildJsonLd(): Record<string, unknown> {
  const businessId = `${SITE.url}/#business`;
  return {
    '@context': 'https://schema.org',
    '@graph': [
      {
        '@type': 'LocalBusiness',
        '@id': businessId,
        name: SITE.name,
        url: `${SITE.url}/`,
        telephone: SITE.phoneTel,
        email: SITE.emails.general,
        address: {
          '@type': 'PostalAddress',
          streetAddress: BUSINESS.address.street,
          addressLocality: BUSINESS.address.locality,
          addressRegion: BUSINESS.address.region,
          addressCountry: BUSINESS.address.country,
        },
        openingHours: [...BUSINESS.openingHours],
        image: OG_IMAGE.url,
        areaServed: { '@type': 'Country', name: 'México' },
        sameAs: [SITE.githubSuiteUrl],
      },
      ...CONTACT_SERVICES.map((name) => ({
        '@type': 'Service',
        name,
        provider: { '@id': businessId },
        areaServed: { '@type': 'Country', name: 'México' },
      })),
    ],
  };
}

@Injectable({ providedIn: 'root' })
export class SeoService {
  private readonly router = inject(Router);
  private readonly title = inject(Title);
  private readonly meta = inject(Meta);
  private readonly document = inject(DOCUMENT);

  init(): void {
    this.router.events.pipe(filter((e): e is NavigationEnd => e instanceof NavigationEnd)).subscribe((e) => {
      const data = this.deepest(this.router.routerState.snapshot.root).data;
      this.apply(e.urlAfterRedirects, data['description'] as string | undefined, data['jsonLd'] === 'home');
    });
  }

  private deepest(route: ActivatedRouteSnapshot): ActivatedRouteSnapshot {
    return route.firstChild ? this.deepest(route.firstChild) : route;
  }

  private apply(url: string, description: string | undefined, withJsonLd: boolean): void {
    const path = url.split(/[?#]/)[0];
    const canonical = `${SITE.url}${path === '/' ? '/' : path.replace(/\/$/, '')}`;
    const title = this.title.getTitle();

    this.setLink('canonical', canonical);
    if (description) this.meta.updateTag({ name: 'description', content: description });
    this.meta.updateTag({ property: 'og:title', content: title });
    if (description) this.meta.updateTag({ property: 'og:description', content: description });
    this.meta.updateTag({ property: 'og:url', content: canonical });
    this.meta.updateTag({ property: 'og:type', content: 'website' });
    this.meta.updateTag({ property: 'og:locale', content: 'es_MX' });
    this.meta.updateTag({ property: 'og:site_name', content: SITE.name });
    this.meta.updateTag({ property: 'og:image', content: OG_IMAGE.url });
    this.meta.updateTag({ property: 'og:image:width', content: String(OG_IMAGE.width) });
    this.meta.updateTag({ property: 'og:image:height', content: String(OG_IMAGE.height) });
    this.meta.updateTag({ property: 'og:image:alt', content: OG_IMAGE.alt });
    this.meta.updateTag({ name: 'twitter:card', content: 'summary_large_image' });
    this.meta.updateTag({ name: 'twitter:image', content: OG_IMAGE.url });
    this.meta.updateTag({ name: 'twitter:image:alt', content: OG_IMAGE.alt });
    this.setJsonLd(withJsonLd);
  }

  private setLink(rel: string, href: string): void {
    let link = this.document.head.querySelector<HTMLLinkElement>(`link[rel="${rel}"]`);
    if (!link) {
      link = this.document.createElement('link');
      link.setAttribute('rel', rel);
      this.document.head.appendChild(link);
    }
    link.setAttribute('href', href);
  }

  private setJsonLd(enabled: boolean): void {
    this.document.getElementById(JSON_LD_ID)?.remove();
    if (!enabled) return;
    const script = this.document.createElement('script');
    script.id = JSON_LD_ID;
    script.type = 'application/ld+json';
    // Static, trusted data; "<" is escaped so the payload can never close the script element.
    script.textContent = JSON.stringify(buildJsonLd()).replace(/</g, '\\u003c');
    this.document.head.appendChild(script);
  }
}
