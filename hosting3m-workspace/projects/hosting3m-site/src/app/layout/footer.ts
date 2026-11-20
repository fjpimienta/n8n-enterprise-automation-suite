import { Component, inject } from '@angular/core';
import { ConsentService } from '../core/consent';
import { RouterLink } from '@angular/router';
import { SITE } from '../core/site.config';

@Component({
  selector: 'app-footer',
  imports: [RouterLink],
  templateUrl: './footer.html',
})
export class Footer {
  readonly site = SITE;
  readonly consent = inject(ConsentService);
  readonly year = new Date().getFullYear();
}
