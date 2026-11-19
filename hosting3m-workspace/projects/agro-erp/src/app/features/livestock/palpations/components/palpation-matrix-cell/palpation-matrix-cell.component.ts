import { DOCUMENT } from '@angular/common';
import { ChangeDetectionStrategy, Component, ElementRef, Injector, afterNextRender, computed, effect, inject, input, output, signal, untracked, viewChild } from '@angular/core';
import { PalpationEventRow, PalpationHerdRow, ReportStatus } from '../../models/palpation.types';
import { PALPATION_CSV_WRITER, exportPairCsv, exportReadiness } from '../../utils/palpation-campaign-export';
import { cellAnimals } from '../../utils/palpation-campaign-pairs';
import { exportBlockText } from '../../utils/palpation-campaign-view';
import { Campaign } from '../../utils/palpation-campaigns';
import { MatrixCell, buildDeepLink, cellLabel } from '../../utils/palpation-matrix-cells';
import { PalpationPairTableComponent } from '../palpation-pair-table/palpation-pair-table.component';

/**
 * The animals behind ONE cell of the transition matrix, with the same table and cards as the follow-up groups. It says what "sin registro" covers, can
 * copy a link that reopens the same cell (only the two date ranges and the cell id are in it) and can export the list with the same guarded exporter.
 * Presentational: it makes no request and stores nothing; the data is what the report already loaded for the active company.
 */
@Component({
  selector: 'app-palpation-matrix-cell',
  standalone: true,
  imports: [PalpationPairTableComponent],
  templateUrl: './palpation-matrix-cell.component.html',
  // Own colours for the refusal text, the buttons and the coverage panel: the stock ones are under 4.5:1 on the dark theme.
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
      .palp-action:disabled {
        opacity: 0.65;
      }
      .palp-title:focus {
        outline: 2px solid #206bc4;
        outline-offset: 3px;
      }
      :host-context([data-bs-theme='dark']) .palp-error {
        color: #ff9b9b;
      }
      :host-context([data-bs-theme='dark']) .palp-coverage {
        background-color: rgba(148, 163, 184, 0.12);
      }
      :host-context([data-bs-theme='dark']) .palp-action {
        color: #8ab8ee;
        border-color: #8ab8ee;
      }
      :host-context([data-bs-theme='dark']) .palp-action:hover:not(:disabled) {
        color: #ffffff;
        background-color: #206bc4;
        border-color: #206bc4;
      }
    `,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class PalpationMatrixCellComponent {
  readonly events = input.required<readonly PalpationEventRow[]>();
  readonly herd = input.required<readonly PalpationHerdRow[]>();
  readonly a = input.required<Campaign>();
  readonly b = input.required<Campaign>();
  readonly cell = input.required<MatrixCell>();
  /** How many animals the matrix counts in this cell. The list must have the same number; if it does not, the list is not shown. */
  readonly matrixCount = input.required<number>();
  /** Status of the report and the active company, for the guarded CSV export. The defaults refuse it. */
  readonly reportStatus = input<ReportStatus>('sin-tenant');
  readonly tenantId = input<number | null>(null);

  readonly closed = output<void>();

  private readonly writer = inject(PALPATION_CSV_WRITER);
  private readonly doc = inject(DOCUMENT);
  private readonly injector = inject(Injector);
  private readonly heading = viewChild<ElementRef<HTMLElement>>('heading');

  protected readonly rows = computed(() => cellAnimals(this.events(), this.herd(), this.a(), this.b(), this.cell().from, this.cell().to));
  protected readonly title = computed(() => cellLabel(this.cell(), this.a().label, this.b().label));
  /** The list and the matrix disagree: a defect, never shown as if it were right. */
  protected readonly mismatch = computed(() => this.rows().length !== this.matrixCount());
  /** Animals counted from their events but without a row in the herd view: they have no SINIIGA, category or status in the list. */
  protected readonly unmatched = computed(() => this.rows().filter(r => !r.herdMatched).length);
  protected readonly truncated = computed(() => this.reportStatus() === 'truncado');
  protected readonly readinessText = computed(() => {
    const reason = exportReadiness(this.reportStatus(), this.tenantId());
    return reason === null ? null : exportBlockText(reason);
  });

  protected readonly message = signal<{ readonly kind: 'ok' | 'blocked'; readonly text: string } | null>(null);
  /** The link, shown for the user to copy by hand when the browser does not let the page write to the clipboard. */
  protected readonly manualLink = signal<string | null>(null);

  constructor() {
    // Moves the focus to the title when a cell is opened (or another one is chosen), so a keyboard or screen-reader user lands on the list.
    effect(() => {
      this.cell();
      untracked(() => afterNextRender(() => this.heading()?.nativeElement.focus(), { injector: this.injector }));
    });
  }

  /** The address that reopens this cell: the origin and path of the page plus the two date ranges and the cell id. Nothing else. */
  protected link(): string {
    const { origin, pathname } = this.doc.location;
    return buildDeepLink(`${origin}${pathname}`, this.a(), this.b(), this.cell());
  }

  protected async copyLink(): Promise<void> {
    const link = this.link();
    this.manualLink.set(null);
    try {
      const clipboard = this.doc.defaultView?.navigator?.clipboard;
      if (!clipboard) throw new Error('clipboard unavailable');
      await clipboard.writeText(link);
      this.message.set({ kind: 'ok', text: 'Enlace copiado. Lleva solo las dos campañas y la celda; los datos salen de la empresa activa.' });
    } catch {
      this.manualLink.set(link);
      this.message.set({ kind: 'ok', text: 'No se pudo copiar solo. Copia el enlace de abajo.' });
    }
  }

  protected export(): void {
    const plan = exportPairCsv(
      { status: this.reportStatus(), tenantId: this.tenantId(), events: this.events(), herd: this.herd(), a: this.a(), b: this.b(), cell: this.cell() },
      this.writer,
    );
    this.message.set(plan.ok ? { kind: 'ok', text: `Archivo generado: ${plan.filename} (${plan.rows.length} animales).` } : { kind: 'blocked', text: exportBlockText(plan.reason) });
  }
}
