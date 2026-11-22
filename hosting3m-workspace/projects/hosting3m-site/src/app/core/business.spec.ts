import { BUSINESS, BUSINESS_ADDRESS_LINE } from './business';
import { buildJsonLd } from './seo';

describe('business data (single source of truth)', () => {
  it('feeds the JSON-LD address and machine-readable hours', () => {
    const graph = buildJsonLd()['@graph'] as Record<string, unknown>[];
    const business = graph.find((n) => n['@type'] === 'LocalBusiness')!;
    expect(business['address']).toMatchObject({ streetAddress: BUSINESS.address.street, addressLocality: 'Mérida', addressRegion: 'Yucatán', addressCountry: 'MX' });
    expect(business['openingHours']).toEqual(['Mo-Fr 09:00-17:00', 'Sa 09:00-14:00']);
  });

  it('builds the one-line address from the same fields and never invents a postal code', () => {
    expect(BUSINESS_ADDRESS_LINE).toBe('Calle 12D #895, Fracc. Solana, Mérida, Yucatán');
    expect(JSON.stringify(BUSINESS)).not.toMatch(/postal|zip|\bCP\b/i);
  });
});
