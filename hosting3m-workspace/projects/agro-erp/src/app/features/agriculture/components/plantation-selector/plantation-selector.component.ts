import { ChangeDetectionStrategy, Component, inject } from '@angular/core';
import { PlantationContextService } from '../../services/plantation-context.service';

/** Active-plantation selector shown next to the company selector, only for palm companies. */
@Component({
  selector: 'app-plantation-selector',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    @if (context.isPalmCompany()) {
      @switch (context.status()) {
        @case ('loading') {
          <span class="text-muted small"><span class="spinner-border spinner-border-sm me-1" role="status"></span>Plantaciones…</span>
        }
        @case ('error') {
          <span class="text-danger small" [title]="context.error() ?? ''"><i class="ti ti-alert-triangle me-1"></i>Sin plantaciones</span>
        }
        @default {
          @if (context.availablePlantations().length > 0) {
            <select class="form-select form-select-sm border-success" style="max-width: 14rem;" aria-label="Plantación activa"
              title="Plantación activa" (change)="onSelect($any($event.target).value)">
              @for (p of context.availablePlantations(); track p.id) {
                <option [value]="p.id" [selected]="p.id === context.activePlantationId()">
                  🌴 {{ p.name }}{{ p.isDefault ? ' (predeterminada)' : '' }}
                </option>
              }
            </select>
          } @else if (context.status() === 'ready') {
            <span class="text-muted small"><i class="ti ti-plant-off me-1"></i>Sin plantaciones activas</span>
          }
        }
      }
    }
  `,
})
export class PlantationSelectorComponent {
  context = inject(PlantationContextService);

  onSelect(plantationId: string) {
    this.context.select(plantationId);
  }
}
