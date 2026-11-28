import { ChangeDetectionStrategy, Component, computed, input } from '@angular/core';
import { CHIP_LABEL, ChipKind } from '../logic/es-mx';

@Component({
  selector: 'app-status-chip',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `<span class="h-chip" [class]="'h-chip h-chip--' + cssKind()">{{ text() }}</span>`
})
export class StatusChipComponent {
  readonly kind = input.required<ChipKind>();
  /** Overrides the default Spanish label. */
  readonly label = input<string | null>(null);
  protected readonly text = computed(() => this.label() ?? CHIP_LABEL[this.kind()]);
  /** "reserved" shares the neutral palette. */
  protected readonly cssKind = computed(() => (this.kind() === 'reserved' ? 'neutral' : this.kind()));
}
