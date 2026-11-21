import { ChangeDetectionStrategy, Component, computed, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { ContactPrefill } from '../core/contact-prefill';
import { PlansService } from '../core/plans';
import { recommend } from '../core/picker';
import { NeedId, SELECTOR } from '../data/home-copy';
import { Icon } from './icon';

@Component({
  selector: 'app-service-picker',
  imports: [RouterLink, Icon],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './service-picker.html',
})
export class ServicePicker {
  private readonly catalog = inject(PlansService);
  private readonly prefill = inject(ContactPrefill);

  readonly copy = SELECTOR;
  readonly selectedId = signal<NeedId>('server');
  readonly selected = computed(() => SELECTOR.options.find((o) => o.id === this.selectedId()) ?? SELECTOR.options[0]);
  /** Recommendation and price come from the catalog; with no catalog data the price is a quote. */
  readonly recommendation = computed(() => recommend(this.catalog.plans(), this.selected().family));
  readonly title = computed(() => this.recommendation().planName ?? this.selected().fallbackTitle);
  readonly price = computed(() => this.recommendation().priceLabel ?? SELECTOR.quote);

  pick(id: NeedId): void {
    this.selectedId.set(id);
  }

  /** The anchor goes to #contacto; this preselects the service and (only if the message is empty or ours) the text. */
  requestQuote(): void {
    this.prefill.apply(this.selected().service, `Quiero cotizar: ${this.title()}`);
  }
}
