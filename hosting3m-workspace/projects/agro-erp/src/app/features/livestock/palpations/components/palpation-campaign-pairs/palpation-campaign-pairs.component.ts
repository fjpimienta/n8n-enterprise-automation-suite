import { NgTemplateOutlet } from '@angular/common';
import { ChangeDetectionStrategy, Component, computed, inject, input, signal } from '@angular/core';
import { PalpationEventRow, PalpationHerdRow, ReportStatus } from '../../models/palpation.types';
import { PALPATION_CSV_WRITER, exportPairCsv, exportReadiness } from '../../utils/palpation-campaign-export';
import { PairGroup, pairLists } from '../../utils/palpation-campaign-pairs';
import { GROUP_LABEL, exportBlockText } from '../../utils/palpation-campaign-view';
import { Campaign } from '../../utils/palpation-campaigns';
import { PalpationPairTableComponent } from '../palpation-pair-table/palpation-pair-table.component';

/**
 * Follow-up of the cows that were Vacía in campaign A: the ones still Vacía in B (persistent) and the ones not palpated in B (pending), a coverage
 * note so nobody reads the lists as complete, and the CSV export. Presentational: it receives the rows of the report and the report status, makes no
 * request and stores nothing. The export is guarded (see `exportPairCsv`): it needs a complete, ready report, a valid company and rows of that company only.
 */
@Component({
  selector: 'app-palpation-campaign-pairs',
  standalone: true,
  imports: [NgTemplateOutlet, PalpationPairTableComponent],
  templateUrl: './palpation-campaign-pairs.component.html',
  // Own colours for the text that carries a refusal, the export button and the coverage panel: the stock ones are under 4.5:1 on the dark theme.
  styles: [
    `
      .palp-error {
        color: #b42323;
      }
      .palp-coverage {
        padding: 0.75rem 1rem;
        border-left: 3px solid #94a3b8;
        border-radius: 4px;
        background-color: rgba(100, 116, 139, 0.1);
      }
      .palp-export:disabled {
        opacity: 0.65;
      }
      :host-context([data-bs-theme='dark']) .palp-error {
        color: #ff9b9b;
      }
      :host-context([data-bs-theme='dark']) .palp-coverage {
        background-color: rgba(148, 163, 184, 0.12);
      }
      :host-context([data-bs-theme='dark']) .palp-export {
        color: #8ab8ee;
        border-color: #8ab8ee;
      }
      :host-context([data-bs-theme='dark']) .palp-export:hover:not(:disabled) {
        color: #ffffff;
        background-color: #206bc4;
        border-color: #206bc4;
      }
    `,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class PalpationCampaignPairsComponent {
  readonly events = input.required<readonly PalpationEventRow[]>();
  readonly herd = input.required<readonly PalpationHerdRow[]>();
  readonly a = input.required<Campaign>();
  readonly b = input.required<Campaign>();
  /** Status of the report. The default refuses the export: a parent has to say the report is ready. */
  readonly reportStatus = input<ReportStatus>('sin-tenant');
  /** The active company, or null when it is missing or ambiguous. The default refuses the export. */
  readonly tenantId = input<number | null>(null);

  private readonly writer = inject(PALPATION_CSV_WRITER);

  private readonly lists = computed(() => pairLists(this.events(), this.herd(), this.a(), this.b()));
  protected readonly persistent = computed(() => this.lists().persistent);
  protected readonly pending = computed(() => this.lists().pending);
  protected readonly coverage = computed(() => this.lists().coverage);

  /** Why the export is refused right now (company or report), or null. The button is disabled with this text next to it. */
  protected readonly readinessText = computed(() => {
    const reason = exportReadiness(this.reportStatus(), this.tenantId());
    return reason === null ? null : exportBlockText(reason);
  });

  protected readonly message = signal<{ readonly kind: 'ok' | 'blocked'; readonly text: string } | null>(null);

  protected export(): void {
    const plan = exportPairCsv(
      { status: this.reportStatus(), tenantId: this.tenantId(), events: this.events(), herd: this.herd(), a: this.a(), b: this.b() },
      this.writer,
    );
    this.message.set(plan.ok ? { kind: 'ok', text: `Archivo generado: ${plan.filename} (${plan.rows.length} animales).` } : { kind: 'blocked', text: exportBlockText(plan.reason) });
  }

  protected titleOf(group: PairGroup): string {
    return GROUP_LABEL[group];
  }
}
