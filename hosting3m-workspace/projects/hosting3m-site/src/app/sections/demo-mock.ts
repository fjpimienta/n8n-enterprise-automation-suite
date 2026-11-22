import { ChangeDetectionStrategy, Component, input } from '@angular/core';
import { AGRO_CHAT, DEMO_TABS, DemoTab, HOTEL_MOCK, WHATSAPP_CHAT } from '../data/systems-demo';

/** One static, illustrative mock screen (fictitious data, built with HTML/CSS). Shared by the home and the portfolio. */
@Component({
  selector: 'app-demo-mock',
  changeDetection: ChangeDetectionStrategy.OnPush,
  host: { class: 'block' },
  templateUrl: './demo-mock.html',
})
export class DemoMock {
  readonly kind = input.required<DemoTab>();
  readonly hotel = HOTEL_MOCK;
  readonly agro = AGRO_CHAT;
  readonly whatsapp = WHATSAPP_CHAT;
  readonly labels = { hotel: DEMO_TABS[0].mockLabel, agro: DEMO_TABS[1].mockLabel, whatsapp: DEMO_TABS[2].mockLabel };
}
