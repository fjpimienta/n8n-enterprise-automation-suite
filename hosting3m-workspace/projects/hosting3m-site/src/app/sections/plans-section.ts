import { ChangeDetectionStrategy, Component, afterNextRender, computed, inject, signal } from '@angular/core';
import { Router, RouterLink } from '@angular/router';
import {
  CatalogPlan,
  PlansService,
  QUOTE_CARDS,
  formatDate,
  formatMoney,
  groupByFamily,
  isQuote,
  priceSuffix,
  quoteHref,
  setupLine,
  shownAmount,
} from '../core/plans';
import { SITE, whatsappLink } from '../core/site.config';

@Component({
  selector: 'app-plans-section',
  imports: [RouterLink],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './plans-section.html',
})
export class PlansSection {
  private readonly catalog = inject(PlansService);
  private readonly router = inject(Router);

  readonly site = SITE;
  readonly cards = QUOTE_CARDS;
  readonly groups = computed(() => groupByFamily(this.catalog.plans()));
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

  /** The WhatsApp link opens in a new tab; this also preselects the service in the contact form. */
  preselect(service: string): void {
    if (service) void this.router.navigate(['/'], { queryParams: { servicio: service }, fragment: 'contacto' });
  }
}
