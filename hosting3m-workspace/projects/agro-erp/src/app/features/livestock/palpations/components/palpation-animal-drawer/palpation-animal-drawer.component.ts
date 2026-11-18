import { DOCUMENT } from '@angular/common';
import {
  ChangeDetectionStrategy,
  Component,
  ElementRef,
  OnDestroy,
  OnInit,
  afterNextRender,
  computed,
  inject,
  input,
  output,
  signal,
  viewChild,
} from '@angular/core';
import { ReportErrorReason } from '../../models/palpation.types';
import { PalpationReportService } from '../../services/palpation-report.service';
import {
  HISTORICAL_BADGE,
  PalpationTableRow,
  RANCH_BADGE,
  SUBTYPE_LABEL,
  TimelineEntry,
  UNCONFIRMED_BADGE,
  buildTimeline,
  formatDate,
  formatGestation,
  reasonText,
} from '../../utils/palpation-view';

type Phase = 'cargando' | 'listo' | 'error';

const FOCUSABLE =
  'button:not([disabled]), [href], input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])';

/**
 * Side panel with the palpation timeline of one animal. It reuses the repo's modal pattern (Tabler `modal` with a dark backdrop, as in
 * `MetadataDetailModalComponent`) styled as a panel on the right, and adds what that pattern lacks: `role="dialog"` with `aria-modal`,
 * a focus trap, Escape to close and the focus given back to the element that opened it. @angular/cdk is not installed, so the trap is
 * written here. The timeline is loaded with `PalpationReportService.loadHistory` (company and role are checked there).
 */
@Component({
  selector: 'app-palpation-animal-drawer',
  standalone: true,
  templateUrl: './palpation-animal-drawer.component.html',
  styles: [`
    .palp-drawer-dialog { margin: 0 0 0 auto; height: 100%; max-width: min(30rem, 100vw); width: 100%; }
    .palp-drawer-content { height: 100%; border-radius: 0; }
    .palp-drawer-content .modal-body { overflow-y: auto; }
  `],
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class PalpationAnimalDrawerComponent implements OnInit, OnDestroy {
  private readonly service = inject(PalpationReportService);
  private readonly document = inject(DOCUMENT);

  readonly animal = input.required<PalpationTableRow>();
  /** The element that opened the drawer. It gets the focus back on close. */
  readonly opener = input<HTMLElement | null>(null);
  readonly closed = output<void>();

  private readonly panel = viewChild.required<ElementRef<HTMLElement>>('panel');
  private readonly closeButton = viewChild.required<ElementRef<HTMLButtonElement>>('closeButton');

  /** Fallback for the focus return when no opener is given. */
  private readonly previousFocus = this.document.activeElement as HTMLElement | null;
  private destroyed = false;

  protected readonly phase = signal<Phase>('cargando');
  protected readonly reason = signal<ReportErrorReason | null>(null);
  protected readonly entries = signal<readonly TimelineEntry[]>([]);

  /** Events that count as a palpation (NR does not). */
  protected readonly counted = computed(() => this.entries().filter(e => e.counts).length);
  protected readonly detail = computed(() => reasonText(this.reason()));

  protected readonly ranchBadge = RANCH_BADGE;
  protected readonly historicalBadge = HISTORICAL_BADGE;
  protected readonly unconfirmedBadge = UNCONFIRMED_BADGE;
  protected readonly formatDate = formatDate;
  protected readonly formatGestation = formatGestation;

  constructor() {
    this.document.body.classList.add('modal-open');
    afterNextRender(() => this.closeButton().nativeElement.focus());
  }

  /** Required inputs have no value in the constructor, so the timeline is loaded here. */
  ngOnInit(): void {
    void this.load();
  }

  ngOnDestroy(): void {
    this.destroyed = true;
    this.document.body.classList.remove('modal-open');
    const target = this.opener() ?? this.previousFocus;
    if (target && target.isConnected) target.focus();
  }

  protected async load(): Promise<void> {
    this.phase.set('cargando');
    this.reason.set(null);
    const result = await this.service.loadHistory(this.animal().livestockId);
    if (this.destroyed) return;
    if (result.ok) {
      this.entries.set(buildTimeline(result.rows));
      this.phase.set('listo');
    } else {
      this.entries.set([]);
      this.reason.set(result.reason);
      this.phase.set('error');
    }
  }

  protected subtypeText(entry: TimelineEntry): string | null {
    if (entry.subtype === null || entry.subtype === 'SIN_CONFIRMAR') return null;
    return SUBTYPE_LABEL[entry.subtype];
  }

  protected showUnconfirmed(entry: TimelineEntry): boolean {
    return entry.unconfirmed || entry.subtype === 'SIN_CONFIRMAR';
  }

  protected onBackdrop(event: MouseEvent): void {
    if (event.target === event.currentTarget) this.closed.emit();
  }

  /** Escape closes; Tab and Shift+Tab stay inside the panel. */
  protected onKeydown(event: KeyboardEvent): void {
    if (event.key === 'Escape') {
      event.preventDefault();
      this.closed.emit();
      return;
    }
    if (event.key !== 'Tab') return;
    const panel = this.panel().nativeElement;
    const focusable = [...panel.querySelectorAll<HTMLElement>(FOCUSABLE)];
    if (focusable.length === 0) {
      event.preventDefault();
      panel.focus();
      return;
    }
    const first = focusable[0]!;
    const last = focusable[focusable.length - 1]!;
    const active = this.document.activeElement as HTMLElement | null;
    const inside = active !== null && panel.contains(active);
    if (event.shiftKey) {
      if (!inside || active === first) {
        event.preventDefault();
        last.focus();
      }
    } else if (!inside || active === last) {
      event.preventDefault();
      first.focus();
    }
  }
}
