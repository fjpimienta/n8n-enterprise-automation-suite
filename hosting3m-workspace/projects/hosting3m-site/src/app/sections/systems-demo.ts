import { ChangeDetectionStrategy, Component, ElementRef, inject, signal, viewChildren } from '@angular/core';
import { RouterLink } from '@angular/router';
import { ContactPrefill } from '../core/contact-prefill';
import { AGRO_CHAT, DEMO_CTAS, DEMO_TABS, DemoTab, HOTEL_MOCK, SYSTEMS_SECTION, WHATSAPP_CHAT } from '../data/systems-demo';

/** "Míralo en acción": static, illustrative mock screens. No ERP API is ever called from here. */
@Component({
  selector: 'app-systems-demo',
  imports: [RouterLink],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './systems-demo.html',
})
export class SystemsDemo {
  private readonly prefill = inject(ContactPrefill);
  private readonly tabButtons = viewChildren<ElementRef<HTMLButtonElement>>('tabButton');

  readonly section = SYSTEMS_SECTION;
  readonly tabs = DEMO_TABS;
  readonly hotel = HOTEL_MOCK;
  readonly agro = AGRO_CHAT;
  readonly whatsapp = WHATSAPP_CHAT;
  readonly ctas = DEMO_CTAS;
  readonly active = signal<DemoTab>('hotel');

  select(id: DemoTab): void {
    this.active.set(id);
  }

  /** WAI-ARIA tabs: arrows, Home and End move the selection and the focus. */
  onKeydown(event: KeyboardEvent, index: number): void {
    const last = this.tabs.length - 1;
    const next = { ArrowRight: index === last ? 0 : index + 1, ArrowLeft: index === 0 ? last : index - 1, Home: 0, End: last }[event.key];
    if (next === undefined) return;
    event.preventDefault();
    this.select(this.tabs[next].id);
    this.tabButtons()[next]?.nativeElement.focus();
  }

  /** The anchor goes to #contacto; this preselects the demo service and a message (never over the visitor's own text). */
  requestDemo(kind: 'hotel' | 'agro'): void {
    this.prefill.apply(this.ctas[kind].service, this.ctas[kind].message);
  }
}
