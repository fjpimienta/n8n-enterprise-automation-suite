import { DOCUMENT } from '@angular/common';
import { Injectable, inject } from '@angular/core';
import { Meta, Title } from '@angular/platform-browser';
import { ActivatedRouteSnapshot, NavigationEnd, Router } from '@angular/router';
import { filter } from 'rxjs';
import { SITE } from './site.config';
import { CONTACT_SERVICES } from './contact';

const JSON_LD_ID = 'jsonld-site';

/** schema.org graph for the home page. Only verified facts: no ratings, hours, prices or street address. */
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
          addressLocality: 'Mérida',
          addressRegion: 'Yucatán',
          addressCountry: 'MX',
          streetAddress: 'Calle 12D #895, Fracc. Solana',
        },
        // Machine-readable; central Mexico time. Human text: lunes a viernes 9:00 a 17:00 y sábados 9:00 a 14:00.
        openingHours: ['Mo-Fr 09:00-17:00', 'Sa 09:00-14:00'],
        image: 'TODO_OG_IMAGE',
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
    this.meta.updateTag({ property: 'og:image', content: 'TODO_OG_IMAGE' });
    this.meta.updateTag({ name: 'twitter:card', content: 'summary' });
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
