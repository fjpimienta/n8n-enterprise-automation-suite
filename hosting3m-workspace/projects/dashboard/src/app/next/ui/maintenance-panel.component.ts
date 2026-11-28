import { ChangeDetectionStrategy, Component, input, output } from '@angular/core';
import { HIconComponent } from '../../shared/ui/h-icon/h-icon.component';

export interface MaintenanceRoom { id: number; number: string }

@Component({
  selector: 'app-maintenance-panel',
  standalone: true,
  imports: [HIconComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <section class="h-card" aria-label="Mantenimiento abierto">
      <h2 class="h-section-title"><app-h-icon name="tool" [size]="18" /> Mantenimiento abierto</h2>
      @if (rooms() === null) {
        <p class="h-empty">Sin datos</p>
      } @else if (rooms()!.length === 0) {
        <p class="h-empty">Sin reportes abiertos</p>
      } @else {
        <div class="h-filters" role="list">
          @for (r of rooms()!; track r.id) {
            <button type="button" role="listitem" class="h-filter" (click)="select.emit(r.id)" [attr.aria-label]="'Ver mantenimiento de la habitación ' + r.number">
              <span class="h-chip h-chip--maintenance">{{ r.number }}</span>
            </button>
          }
        </div>
      }
    </section>`
})
export class MaintenancePanelComponent {
  /** Rooms flagged with a pending ticket; `null` = unknown. */
  readonly rooms = input.required<MaintenanceRoom[] | null>();
  readonly select = output<number>();
}
