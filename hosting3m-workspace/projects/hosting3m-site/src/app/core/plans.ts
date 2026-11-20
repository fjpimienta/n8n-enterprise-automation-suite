import catalog from '../data/plans.json';

export interface Plan {
  readonly id: string;
  readonly name: string;
  readonly summary: string;
  /** Number once approved by the owner; `TODO_PRICE` while pending. */
  readonly price: number | string;
  readonly billing: string;
  readonly features: readonly string[];
  /** Value for the contact form `service` field (server limit: 60 characters). */
  readonly service: string;
}

export const PLANS: readonly Plan[] = catalog.plans;
export const PLANS_CURRENCY: string = catalog.currency;

export function isPending(value: string | number): boolean {
  return typeof value === 'string' && value.startsWith('TODO_');
}

export function formatPrice(plan: Plan): string | null {
  return typeof plan.price === 'number'
    ? new Intl.NumberFormat('es-MX', { style: 'currency', currency: PLANS_CURRENCY }).format(plan.price)
    : null;
}
