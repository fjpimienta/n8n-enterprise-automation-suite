import { Component } from '@angular/core';
import { TestBed } from '@angular/core/testing';
import { Router, provideRouter } from '@angular/router';
import { PROFILE } from '../data/profile';
import { Profile } from '../pages/profile';
import { SeoService, buildPersonJsonLd } from './seo';
import { SITE } from './site.config';

@Component({ template: '' })
class Blank {}

const ld = () => document.head.querySelector<HTMLScriptElement>('script#jsonld-site');

describe('Person JSON-LD', () => {
  it('parses and every field matches what /fjpimienta shows', () => {
    const person = JSON.parse(JSON.stringify(buildPersonJsonLd()));
    const fixture = TestBed.createComponent(Profile);
    fixture.detectChanges();
    const el = fixture.nativeElement as HTMLElement;
    const text = el.textContent ?? '';
    expect(person['@type']).toBe('Person');
    expect(el.querySelector('h1')?.textContent?.trim()).toBe(person.name);
    expect(text).toContain(person.jobTitle);
    expect(text).toContain(`${person.address.addressLocality}, ${person.address.addressRegion}`);
    expect(person.url).toBe(`${SITE.url}/fjpimienta`);
    expect(person.image).toBe(`${SITE.url}${el.querySelector('img')!.getAttribute('src')}`);
    const links = Array.from(el.querySelectorAll('a')).map((a) => a.getAttribute('href'));
    for (const url of person.sameAs as string[]) expect(links).toContain(url);
    expect(person.sameAs).toEqual([PROFILE.linkedin.url]);
    expect(JSON.stringify(person)).not.toMatch(/gmail|[a-z]@[a-z]|tel:|github/i);
    expect(Object.keys(person).sort()).toEqual(['@context', '@id', '@type', 'address', 'image', 'jobTitle', 'name', 'sameAs', 'url']);
  });

  it('is emitted only on /fjpimienta; home keeps its graph', async () => {
    TestBed.configureTestingModule({
      providers: [
        provideRouter([
          { path: '', pathMatch: 'full', component: Blank, data: { jsonLd: 'home' } },
          { path: 'fjpimienta', component: Blank, data: { jsonLd: 'person' } },
          { path: 'portfolio', component: Blank },
        ]),
      ],
    });
    TestBed.inject(SeoService).init();
    const router = TestBed.inject(Router);
    await router.navigateByUrl('/fjpimienta');
    expect(JSON.parse(ld()!.textContent!)['@type']).toBe('Person');
    await router.navigateByUrl('/portfolio');
    expect(ld()).toBeNull();
    await router.navigateByUrl('/');
    expect(JSON.parse(ld()!.textContent!)['@graph'][0]['@type']).toBe('LocalBusiness');
    await router.navigateByUrl('/fjpimienta');
    expect(document.head.querySelectorAll('script#jsonld-site')).toHaveLength(1);
  });
});
