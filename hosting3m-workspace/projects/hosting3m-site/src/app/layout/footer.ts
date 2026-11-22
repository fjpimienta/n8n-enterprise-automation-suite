import { Component, inject } from '@angular/core';
import { RouterLink } from '@angular/router';
import { BUSINESS, BUSINESS_ADDRESS_LINE } from '../core/business';
import { ConsentService } from '../core/consent';
import { SITE } from '../core/site.config';

@Component({
  selector: 'app-footer',
  imports: [RouterLink],
  templateUrl: './footer.html',
})
export class Footer {
  readonly site = SITE;
  readonly business = BUSINESS;
  readonly addressLine = BUSINESS_ADDRESS_LINE;
  readonly consent = inject(ConsentService);
  readonly year = new Date().getFullYear();
}
