import { FALLBACK_NEWS, safeHttpUrl, sanitizeNews } from './news';

describe('safeHttpUrl', () => {
  it('accepts http and https only', () => {
    expect(safeHttpUrl('https://example.com/a')).toBe('https://example.com/a');
    expect(safeHttpUrl('http://example.com/a')).toBe('http://example.com/a');
    for (const bad of ['javascript:alert(1)', 'data:text/html,<b>x</b>', 'ftp://x.com', '//evil.com', 'not a url', '', null, 42]) {
      expect(safeHttpUrl(bad)).toBeNull();
    }
  });

  it('can require https (images)', () => {
    expect(safeHttpUrl('http://example.com/i.png', true)).toBeNull();
    expect(safeHttpUrl('https://example.com/i.png', true)).not.toBeNull();
  });
});

describe('sanitizeNews', () => {
  it('returns [] for non-arrays and for the empty-collection shape [{}]', () => {
    expect(sanitizeNews(null)).toEqual([]);
    expect(sanitizeNews({ title: 'x' })).toEqual([]);
    expect(sanitizeNews([{}])).toEqual([]);
  });

  it('drops items with an unsafe url and keeps strings as plain text', () => {
    const items = sanitizeNews([
      { title: '<img src=x onerror=alert(1)>', url: 'https://ok.example/n', source: 'S', image: 'javascript:1', published_at: '2026-01-02T00:00:00Z' },
      { title: 'bad', url: 'javascript:alert(1)' },
    ]);
    expect(items).toHaveLength(1);
    expect(items[0].title).toBe('<img src=x onerror=alert(1)>'); // rendered via binding, so inert
    expect(items[0].image).toBeNull();
    expect(items[0].publishedAt?.getUTCFullYear()).toBe(2026);
  });

  it('ignores invalid dates and caps the list', () => {
    const many = Array.from({ length: 20 }, (_, i) => ({ title: `t${i}`, url: `https://x.example/${i}`, published_at: 'nope' }));
    const items = sanitizeNews(many);
    expect(items).toHaveLength(6);
    expect(items[0].publishedAt).toBeNull();
  });
});

describe('fallback news', () => {
  it('has 3 own cards with safe urls', () => {
    expect(FALLBACK_NEWS).toHaveLength(3);
    for (const n of FALLBACK_NEWS) expect(safeHttpUrl(n.url)).not.toBeNull();
  });
});
