import { ChangeDetectionStrategy, Component } from '@angular/core';

/**
 * The neutral note of the campaign views ("Compara resultados de palpación; no explica causas."). It sets its own text colour for both themes: the
 * stock grey alert was 3.4:1 on the dark theme. A note, not a warning: it carries `role="note"` and its meaning is in the words.
 */
@Component({
  selector: 'app-palp-note',
  standalone: true,
  template: '<ng-content />',
  host: { role: 'note' },
  styles: [
    `
      :host {
        display: block;
        margin-bottom: 1rem;
        padding: 0.75rem 1rem;
        border-left: 3px solid #94a3b8;
        border-radius: 4px;
        background-color: rgba(100, 116, 139, 0.1);
        color: #334155;
      }
      :host-context([data-bs-theme='dark']) {
        background-color: rgba(148, 163, 184, 0.12);
        color: #dbe3ee;
      }
    `,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class PalpationNoteComponent {}
