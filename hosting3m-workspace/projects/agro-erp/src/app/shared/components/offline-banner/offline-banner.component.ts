import { ChangeDetectionStrategy, Component, computed, input } from '@angular/core';

/** Banner shown while the inventory is served from the offline snapshot (#1087, phase 1b-iii-a). */
@Component({
  selector: 'app-offline-banner',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    @if (visible()) {
      <div class="alert alert-warning d-print-none mb-3" role="status">
        Mostrando datos guardados{{ savedLabel() }}. Sin conexión: los cambios no se guardarán.
      </div>
    }
  `
})
export class OfflineBannerComponent {
  readonly servedFromCache = input<boolean>(false);
  readonly savedAt = input<string | null>(null);

  readonly visible = computed(() => this.servedFromCache());

  readonly savedLabel = computed(() => {
    const raw = this.savedAt();
    if (!raw) return '';
    const date = new Date(raw);
    if (isNaN(date.getTime())) return '';
    return ` el ${date.toLocaleString('es-MX')}`;
  });
}
