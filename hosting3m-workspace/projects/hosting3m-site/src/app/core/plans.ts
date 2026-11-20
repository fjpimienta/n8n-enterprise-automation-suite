import { Injectable, computed, inject, signal } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { timeout } from 'rxjs';
import { RUNTIME } from './runtime-config';
import { whatsappLink } from './site.config';
import catalog from '../data/plans.json';
import snapshot from '../data/plans-snapshot.json';

/** Static quote card, shown only while the public catalog is empty. Carries no price. */
export interface QuoteCard {
  readonly id: string;
  readonly name: string;
  readonly summary: string;
  /** Value for the contact form `service` field (server limit: 60 characters). */
  readonly service: string;
}
export const QUOTE_CARDS: readonly QuoteCard[] = catalog.plans;

export const FAMILIES = ['vps', 'domain', 'hosting', 'cloud', 'email', 'automation', 'web'] as const;
export type PlanFamily = (typeof FAMILIES)[number];
export const BILLING_PERIODS = ['monthly', 'yearly', 'usage', 'one_time', 'quote'] as const;
export type BillingPeriod = (typeof BILLING_PERIODS)[number];

export const FAMILY_TITLES: Record<PlanFamily, string> = {
  vps: 'Servidores VPS',
  domain: 'Dominios',
  hosting: 'Hosting',
  cloud: 'Nube',
  email: 'Correo electrónico',
  automation: 'Automatización',
  web: 'Sitios web',
};

/** A plan of the public catalog after validation. Everything here is safe to bind in templates. */
export interface CatalogPlan {
  readonly key: string;
  readonly family: PlanFamily;
  readonly name: string;
  readonly summary: string;
  readonly features: readonly string[];
  readonly badge: string | null;
  readonly billing: BillingPeriod;
  readonly price: number | null;
  readonly managedPrice: number | null;
  readonly promoPrice: number | null;
  readonly promoMonths: number | null;
  readonly renewalPrice: number | null;
  readonly setupFee: number | null;
  readonly termMonths: number | null;
  readonly currency: string;
  /** null when the API does not say: then no tax wording is shown. */
  readonly taxIncluded: boolean | null;
  /** Contact form `service` value (max 60 characters, the server limit). */
  readonly serviceLabel: string;
  readonly priceCheckedAt: Date | null;
  readonly validUntil: Date | null;
  readonly featured: boolean;
  readonly sortOrder: number;
}

export const MAX_PLANS = 50;
const MAX_FEATURES = 20;

function text(value: unknown, max: number): string {
  return typeof value === 'string' ? value.trim().slice(0, max) : '';
}

/** Amount: a finite number >= 0. Postgres numerics may arrive as numeric strings, so those are parsed too. */
function amount(value: unknown): number | null {
  const n = typeof value === 'number' ? value : typeof value === 'string' && /^\d+(\.\d+)?$/.test(value.trim()) ? Number(value) : NaN;
  return Number.isFinite(n) && n >= 0 ? n : null;
}

function count(value: unknown): number | null {
  const n = amount(value);
  return n !== null && Number.isInteger(n) && n <= 1200 ? n : null;
}

function date(value: unknown): Date | null {
  if (typeof value !== 'string' || value.length > 40) return null;
  const d = new Date(value);
  return Number.isNaN(d.getTime()) ? null : d;
}

/** Type guard for the untrusted POST /v6/plans answer: unknown fields are ignored, invalid entries are skipped. */
export function parsePlans(raw: unknown): CatalogPlan[] {
  if (!Array.isArray(raw)) return [];
  const plans: CatalogPlan[] = [];
  const seen = new Set<string>();
  for (const entry of raw) {
    if (plans.length >= MAX_PLANS) break;
    if (typeof entry !== 'object' || entry === null) continue;
    const e = entry as Record<string, unknown>;
    const key = text(e['plan_key'], 60);
    const name = text(e['name'], 80);
    const family = FAMILIES.find((f) => f === e['family']);
    if (!key || !name || !family || seen.has(key)) continue; // an empty collection may arrive as [{}]
    seen.add(key);
    const billing = BILLING_PERIODS.find((b) => b === e['billing_period']) ?? 'quote';
    const currency = typeof e['currency'] === 'string' && /^[A-Z]{3}$/.test(e['currency']) ? e['currency'] : 'MXN';
    plans.push({
      key,
      family,
      name,
      summary: text(e['summary'], 300),
      features: Array.isArray(e['features'])
        ? e['features'].map((f) => text(f, 160)).filter(Boolean).slice(0, MAX_FEATURES)
        : [],
      badge: text(e['badge'], 40) || null,
      billing,
      price: amount(e['price_amount']),
      managedPrice: amount(e['managed_amount']),
      promoPrice: amount(e['promo_amount']),
      promoMonths: count(e['promo_months']),
      renewalPrice: amount(e['renewal_amount']),
      setupFee: amount(e['setup_fee']),
      termMonths: count(e['term_months']),
      currency,
      taxIncluded: typeof e['tax_included'] === 'boolean' ? e['tax_included'] : null,
      serviceLabel: text(e['service_label'], 60),
      priceCheckedAt: date(e['price_checked_at']),
      validUntil: date(e['valid_until']),
      featured: e['is_featured'] === true,
      sortOrder: typeof e['sort_order'] === 'number' && Number.isFinite(e['sort_order']) ? e['sort_order'] : 0,
    });
  }
  return plans.sort((a, b) => a.sortOrder - b.sortOrder || a.name.localeCompare(b.name, 'es'));
}

// ---- presentation helpers (pure, unit-tested) ----

export function formatMoney(value: number, currency = 'MXN'): string {
  return new Intl.NumberFormat('es-MX', { style: 'currency', currency }).format(value);
}

/** Price shown for the chosen mode; falls back to the self-managed price when there is no managed one. */
export function shownAmount(plan: CatalogPlan, managed: boolean): number | null {
  return managed && plan.managedPrice !== null ? plan.managedPrice : plan.price;
}

export function isQuote(plan: CatalogPlan, managed: boolean): boolean {
  return plan.billing === 'quote' || shownAmount(plan, managed) === null;
}

const PERIOD_WORD: Record<BillingPeriod, string> = { monthly: '/ mes', yearly: '/ año', usage: '/ uso', one_time: 'pago único', quote: '' };

/** "MXN / año + IVA", "MXN / mes IVA incluido", "MXN pago único + IVA". */
export function priceSuffix(plan: CatalogPlan): string {
  const tax = plan.taxIncluded === true ? 'IVA incluido' : plan.taxIncluded === false ? '+ IVA' : '';
  return [plan.currency, PERIOD_WORD[plan.billing], tax].filter(Boolean).join(' ');
}

/** null means "show no setup line", except VPS plans, which always say the setup is quoted. */
export function setupLine(plan: CatalogPlan): string | null {
  if (plan.setupFee !== null) return plan.setupFee === 0 ? 'Instalación inicial: sin costo' : `Instalación inicial: ${formatMoney(plan.setupFee, plan.currency)}`;
  return plan.family === 'vps' ? 'Instalación inicial: cotiza' : null;
}

export function formatDate(value: Date): string {
  return new Intl.DateTimeFormat('es-MX', { dateStyle: 'long', timeZone: 'UTC' }).format(value);
}

export function quoteMessage(plan: CatalogPlan): string {
  return `Hola, quiero cotizar ${plan.name}${plan.serviceLabel ? ` (${plan.serviceLabel})` : ''}.`;
}

export function quoteHref(plan: CatalogPlan): string {
  return whatsappLink(quoteMessage(plan));
}

export interface PlanGroup {
  readonly family: PlanFamily;
  readonly title: string;
  readonly plans: readonly CatalogPlan[];
}

export function groupByFamily(plans: readonly CatalogPlan[]): PlanGroup[] {
  return FAMILIES.map((family) => ({ family, title: FAMILY_TITLES[family], plans: plans.filter((p) => p.family === family) })).filter(
    (g) => g.plans.length > 0,
  );
}

@Injectable({ providedIn: 'root' })
export class PlansService {
  private readonly http = inject(HttpClient);
  private started = false;

  /** Starts from the build-time snapshot (what was prerendered); `refresh()` may replace it once. */
  readonly plans = signal<readonly CatalogPlan[]>(parsePlans(snapshot));
  /** Service labels coming from the catalog, accepted by the contact form besides the static list. */
  readonly serviceLabels = computed(() => [...new Set(this.plans().map((p) => p.serviceLabel).filter(Boolean))]);

  /** Browser only, once. Any error or malformed answer keeps the prerendered catalog. */
  refresh(): void {
    if (this.started || RUNTIME.mockApi) return;
    this.started = true;
    this.http
      .post<unknown>(`${RUNTIME.apiBase}/v6/plans`, {})
      .pipe(timeout(8000))
      .subscribe({
        next: (res) => {
          if (Array.isArray(res)) this.plans.set(parsePlans(res));
        },
        error: () => undefined,
      });
  }
}
