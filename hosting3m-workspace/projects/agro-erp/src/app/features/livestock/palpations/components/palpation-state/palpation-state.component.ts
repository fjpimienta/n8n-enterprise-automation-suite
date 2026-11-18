import { ChangeDetectionStrategy, Component, computed, input, output } from '@angular/core';
import { ReportErrorReason } from '../../models/palpation.types';
import { reasonText } from '../../utils/palpation-view';

/** What the state component can show. Banners (`truncado`, `no-reconocidos`) go above the content; the rest replace it. */
export type PalpationStateKind =
  | 'cargando'
  | 'vacio'
  | 'error'
  | 'sin-permiso'
  | 'sin-tenant'
  | 'sin-campana'
  | 'truncado'
  | 'no-reconocidos';

/**
 * One place for every non-content state of the palpation report, with its Spanish text. Errors show a generic reason, never a response
 * body. `role="alert"` is used where the user must act or must not trust the numbers; `role="status"` for the rest.
 */
@Component({
  selector: 'app-palpation-state',
  standalone: true,
  templateUrl: './palpation-state.component.html',
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class PalpationStateComponent {
  readonly kind = input.required<PalpationStateKind>();
  /** Reason of an `error`. */
  readonly reason = input<ReportErrorReason | null>(null);
  /** Rows loaded (`truncado`) or rows with an unrecognised value (`no-reconocidos`). */
  readonly count = input<number>(0);
  readonly retry = output<void>();
  readonly showAll = output<void>();

  protected readonly detail = computed(() => reasonText(this.reason()));
}
