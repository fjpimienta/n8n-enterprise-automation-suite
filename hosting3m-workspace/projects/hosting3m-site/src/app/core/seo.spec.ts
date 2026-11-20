import { buildJsonLd } from './seo';

describe('buildJsonLd', () => {
  const graph = (buildJsonLd()['@graph'] as Record<string, unknown>[]);

  it('describes one LocalBusiness in Mérida plus its services', () => {
    const business = graph.find((n) => n['@type'] === 'LocalBusiness')!;
    expect((business['address'] as Record<string, string>)['addressLocality']).toBe('Mérida');
    expect(graph.filter((n) => n['@type'] === 'Service').length).toBeGreaterThan(0);
  });

  it('publishes only business contact data, never the personal email', () => {
    expect(JSON.stringify(graph)).not.toContain('gmail.com');
  });
});
