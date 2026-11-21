import { ChangeDetectionStrategy, Component, inject } from '@angular/core';
import { RouterLink } from '@angular/router';
import { ContactPrefill } from '../core/contact-prefill';
import { PORTFOLIO } from '../data/portfolio';
import { DemoMock } from '../sections/demo-mock';

@Component({
  selector: 'app-portfolio',
  imports: [RouterLink, DemoMock],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './portfolio.html',
})
export class Portfolio {
  private readonly prefill = inject(ContactPrefill);
  readonly copy = PORTFOLIO;

  /** Same behavior as the systems section: the anchor goes to #contacto; this preselects the service and the message. */
  requestDemo(kind: 'hotel' | 'agro'): void {
    this.prefill.apply(this.copy.demo[kind].service, this.copy.demo[kind].message);
  }
}
