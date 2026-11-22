import { ChangeDetectionStrategy, Component, afterNextRender, computed, inject, signal } from '@angular/core';
import { Router, RouterLink } from '@angular/router';
import { ContactPrefill } from '../core/contact-prefill';
import {
  CatalogPlan,
  PlansService,
  QUOTE_CARDS,
  formatDate,
  formatMoney,
  MODE_MANAGED,
  MODE_SELF,
  groupByFamily,
  interestMessage,
  isQuote,
  priceSuffix,
  quoteHref,
  setupLine,
  shownAmount,
} from '../core/plans';
import { SITE, whatsappLink } from '../core/site.config';
import { PACKAGES_SECTION } from '../data/home-copy';

@Component({
  selector: 'app-plans-section',
  imports: [RouterLink],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './plans-section.html',
})
export class PlansSection {
  private readonly catalog = inject(PlansService);
  private readonly router = inject(Router);
  private readonly prefill = inject(ContactPrefill);

  readonly modeSelf = MODE_SELF;
  readonly modeManaged = MODE_MANAGED;

  readonly site = SITE;
  readonly copy = PACKAGES_SECTION;
  readonly cards = QUOTE_CARDS;
  readonly groups = computed(() => groupByFamily(this.catalog.plans()));
  /** Per domain group: show the renewal column only when at least one row has a renewal price. */
  hasRenewal(plans: readonly CatalogPlan[]): boolean {
    return plans.some((p) => p.renewalPrice !== null);
  }

  readonly isEmpty = computed(() => this.catalog.plans().length === 0);
  readonly genericQuoteHref = whatsappLink('Hola, quiero una cotización.');
  /** Plans (by key) for which the "Administrado por Hosting3M" price is selected. */
  readonly managed = signal<Readonly<Record<string, boolean>>>({});

  readonly formatMoney = formatMoney;
  readonly formatDate = formatDate;
  readonly priceSuffix = priceSuffix;
  readonly setupLine = setupLine;
  readonly quoteHref = quoteHref;

  constructor() {
    // Refresh the catalog once, after hydration. On any error the prerendered catalog stays.
    afterNextRender(() => this.catalog.refresh());
  }

  isManaged(plan: CatalogPlan): boolean {
    return this.managed()[plan.key] === true && plan.managedPrice !== null;
  }

  setManaged(plan: CatalogPlan, value: boolean): void {
    this.managed.update((m) => ({ ...m, [plan.key]: value }));
  }

  amount(plan: CatalogPlan): number | null {
    return shownAmount(plan, this.isManaged(plan));
  }

  needsQuote(plan: CatalogPlan): boolean {
    return isQuote(plan, this.isManaged(plan));
  }

  /** The WhatsApp link opens in a new tab; this also preselects the service (and the message, if given) in the contact form. */
  preselect(service: string, message = ''): void {
    if (!service) return;
    this.prefill.apply(service, message);
    void this.router.navigate(['/'], { fragment: 'contacto' });
  }

  /** Quote-only plans: the contact form gets the plan name ("Quiero cotizar: <plan>"), like the priced plans. */
  preselectQuote(plan: CatalogPlan): void {
    this.preselect(plan.serviceLabel, interestMessage(plan, false));
  }

  /** One "Precios vigentes al" date per family group: the most recent price_checked_at of its plans. */
  groupDate(plans: readonly CatalogPlan[]): Date | null {
    const dates = plans.map((p) => p.priceCheckedAt).filter((d): d is Date => d !== null);
    return dates.length ? new Date(Math.max(...dates.map((d) => d.getTime()))) : null;
  }

  /** Groups of exactly four plans: 2x2 up to 1279 px and four columns from 1280 px (no orphan card); 1 column on phones. */
  gridClass(count: number): string {
    return count === 4 ? 'sm:grid-cols-2 xl:grid-cols-4' : 'sm:grid-cols-2 lg:grid-cols-3';
  }

  familyNote(family: string): string | null {
    return this.copy.familyNotes[family] ?? null;
  }

  /** "Cotizar <plan>": the routerLink goes to #contacto; this tells the form what to preselect and prefill. */
  requestQuote(plan: CatalogPlan): void {
    this.prefill.apply(plan.serviceLabel, interestMessage(plan, this.isManaged(plan)));
  }
}
