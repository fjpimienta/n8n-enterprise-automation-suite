import { ChangeDetectionStrategy, Component, computed, input } from '@angular/core';
import { MT_REASON_LABEL, MtItem, ageText, issueLabel } from '../logic/maintenance';
import { StatusChipComponent } from './status-chip.component';

/** One open maintenance ticket. Presentational and read-only: it has no actions and never shows cost. */
@Component({
  selector: 'app-maintenance-row',
  standalone: true,
  imports: [StatusChipComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="h-mt__info">
      <span class="h-mt__number">{{ roomNumber() }}</span>
      <app-status-chip kind="reserved" [label]="type()" />
      @if (item().old) { <app-status-chip kind="maintenance" label="Antiguo" /> }
      @if (item().roomState === 'blocked') { <app-status-chip kind="maintenance" label="Bloqueada" /> }
      @if (item().roomState === 'pending') { <app-status-chip kind="cleaning" label="Con falla pendiente" /> }
      @if (item().group === 'review') { <app-status-chip kind="reserved" label="Revisar datos" /> }
    </div>
    <p class="h-mt__desc">{{ description() }}</p>
    <p class="h-mt__meta">Reportada: {{ age() }}</p>
    @if (reasons()) { <p class="h-mt__meta h-mt__meta--review">{{ reasons() }}</p> }`
})
export class MaintenanceRowComponent {
  readonly item = input.required<MtItem>();
  protected readonly roomNumber = computed(() => this.item().room?.number ?? '—');
  protected readonly type = computed(() => issueLabel(this.item().ticket.issueType));
  protected readonly description = computed(() => this.item().ticket.description || 'Sin descripción');
  protected readonly age = computed(() => ageText(this.item().ageDays));
  protected readonly reasons = computed(() => this.item().reasons.map(r => MT_REASON_LABEL[r]).join(' · '));
}
