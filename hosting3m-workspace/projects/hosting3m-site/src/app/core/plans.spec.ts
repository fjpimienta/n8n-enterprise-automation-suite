import { PLANS, formatPrice, isPending } from './plans';

describe('plans catalog', () => {
  it('has the four agreed packages with unique ids', () => {
    expect(PLANS.map((p) => p.id)).toEqual(['vps', 'n8n-managed', 'domains-email', 'launch-pack']);
    expect(new Set(PLANS.map((p) => p.id)).size).toBe(PLANS.length);
  });

  it('keeps every service value within the server limit of 60 characters', () => {
    for (const plan of PLANS) expect(plan.service.length).toBeLessThanOrEqual(60);
  });

  it('never renders a price while it is still a TODO placeholder', () => {
    for (const plan of PLANS) {
      expect(isPending(plan.price)).toBe(true);
      expect(formatPrice(plan)).toBeNull();
    }
  });

  it('formats an approved numeric price in MXN', () => {
    const priced = { ...PLANS[0], price: 1234.5 };
    expect(formatPrice(priced)).toContain('1,234.50');
  });
});
