import { ChangeDetectionStrategy, Component, input } from '@angular/core';

export type IconName = 'server' | 'domain' | 'automation' | 'web' | 'mail' | 'cloud';

/** Outline icons (24x24). Decorative: always aria-hidden; the visible label carries the meaning. */
@Component({
  selector: 'app-icon',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <svg viewBox="0 0 24 24" [attr.width]="size()" [attr.height]="size()" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false">
      @switch (name()) {
        @case ('server') { <rect x="3" y="4" width="18" height="6" rx="1.5" /><rect x="3" y="14" width="18" height="6" rx="1.5" /><path d="M7 7h.01M7 17h.01" /> }
        @case ('domain') { <circle cx="12" cy="12" r="9" /><path d="M3 12h18M12 3c3 3 3 15 0 18M12 3c-3 3-3 15 0 18" /> }
        @case ('automation') { <circle cx="5" cy="6" r="2" /><circle cx="19" cy="12" r="2" /><circle cx="5" cy="18" r="2" /><path d="M7 6h5a3 3 0 013 3v1M7 18h5a3 3 0 003-3v-1" /> }
        @case ('web') { <rect x="3" y="4" width="18" height="16" rx="2" /><path d="M3 9h18M7 6.5h.01" /> }
        @case ('mail') { <rect x="3" y="5" width="18" height="14" rx="2" /><path d="M3 7l9 6 9-6" /> }
        @case ('cloud') { <path d="M7 18a4 4 0 010-8 5.5 5.5 0 0110.6 1.5A3.3 3.3 0 0117 18z" /> }
      }
    </svg>
  `,
})
export class Icon {
  readonly name = input.required<IconName>();
  readonly size = input(28);
}
