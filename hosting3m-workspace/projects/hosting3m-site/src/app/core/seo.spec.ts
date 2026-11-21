import { buildJsonLd } from './seo';

describe('buildJsonLd', () => {
  const graph = (buildJsonLd()['@graph'] as Record<string, unknown>[]);

  it('describes one LocalBusiness in Mérida plus its services', () => {
    const business = graph.find((n) => n['@type'] === 'LocalBusiness')!;
    expect((business['address'] as Record<string, string>)['addressLocality']).toBe('Mérida');
    expect(business['address']).toEqual({
      '@type': 'PostalAddress',
      streetAddress: 'Calle 12D #895, Fracc. Solana',
      addressLocality: 'Mérida',
      addressRegion: 'Yucatán',
      addressCountry: 'MX',
    });
    expect(business['openingHours']).toEqual(['Mo-Fr 09:00-17:00', 'Sa 09:00-14:00']);
    expect(graph.filter((n) => n['@type'] === 'Service').length).toBeGreaterThan(0);
  });

  it('publishes only business contact data, never the personal email', () => {
    expect(JSON.stringify(graph)).not.toContain('gmail.com');
  });
});
