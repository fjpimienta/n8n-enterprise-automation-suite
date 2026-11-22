import { CatalogPlan, formatMoney, isQuote, priceSuffix, shownAmount } from './plans';

export interface Recommendation {
  /** Name of the recommended catalog plan, or null when the catalog has none for this family. */
  readonly planName: string | null;
  /** "Desde $2,880 MXN / año + IVA", or null => show "Cotiza por WhatsApp". Always derived from the catalog. */
  readonly priceLabel: string | null;
}

/**
 * Picks the plan to recommend for a catalog family (featured first, then catalog order) and builds its price label.
 * Prices are never hardcoded: with an empty catalog, or a quote-only plan, the price label is null.
 */
export function recommend(plans: readonly CatalogPlan[], family: CatalogPlan['family']): Recommendation {
  const inFamily = plans.filter((p) => p.family === family);
  const plan = inFamily.find((p) => p.featured) ?? inFamily[0];
  if (!plan) return { planName: null, priceLabel: null };
  const priced = inFamily.filter((p) => !isQuote(p, false));
  if (isQuote(plan, false) || priced.length === 0) return { planName: plan.name, priceLabel: null };
  const cheapest = priced.reduce((a, b) => ((shownAmount(b, false) ?? Infinity) < (shownAmount(a, false) ?? Infinity) ? b : a));
  const amount = shownAmount(cheapest, false) as number;
  const from = priced.length > 1 || cheapest.managedPrice !== null ? 'Desde ' : '';
  return { planName: plan.name, priceLabel: `${from}${formatMoney(amount, cheapest.currency)} ${priceSuffix(cheapest)}` };
}
