import { ChangeDetectionStrategy, Component } from '@angular/core';

/**
 * The "código sin confirmar" flag of the campaign views: a small grey label with the code as typed. The stock Tabler grey badge is 2.9:1 on the dark
 * theme, so this one sets its own text and background for both themes (at least 4.5:1 measured on the real background). The meaning is in the text
 * it wraps ("Sí: DF15"), never in the colour.
 */
@Component({
  selector: 'app-palp-flag',
  standalone: true,
  template: '<ng-content />',
  styles: [
    `
      :host {
        display: inline-block;
        padding: 0.15em 0.55em;
        border-radius: 4px;
        font-size: 0.75rem;
        font-weight: 600;
        line-height: 1.5;
        background-color: rgba(100, 116, 139, 0.16);
        color: #334155;
      }
      :host-context([data-bs-theme='dark']) {
        background-color: rgba(148, 163, 184, 0.24);
        color: #eef2f7;
      }
    `,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class PalpationFlagComponent {}
