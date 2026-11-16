import { ChangeDetectionStrategy, Component, computed, inject, input } from '@angular/core';
import { OfflineSessionService } from '@core/services/offline-session.service';

/** Banner shown while the inventory is served from the offline snapshot (#1087, phase 1b-iii-a). */
@Component({
  selector: 'app-offline-banner',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    @if (visible()) {
      <div class="alert alert-warning d-print-none mb-3" role="status">
        @if (grace()) {
          Sesión vencida. Mostrando datos guardados{{ savedLabel() }} sin conexión. Los cambios no se guardarán
          hasta iniciar sesión en línea.
        } @else {
          Mostrando datos guardados{{ savedLabel() }}. Sin conexión: los cambios no se guardarán.
        }
      </div>
    }
  `
})
export class OfflineBannerComponent {
  readonly servedFromCache = input<boolean>(false);
  readonly savedAt = input<string | null>(null);

  private readonly session = inject(OfflineSessionService);

  /** Grace: the session expired but the copy is readable after the PIN unlock. Says so explicitly. */
  readonly grace = computed(() => this.session.state() === 'grace');
  readonly visible = computed(() => this.servedFromCache());

  readonly savedLabel = computed(() => {
    const raw = this.savedAt();
    if (!raw) return '';
    const date = new Date(raw);
    if (isNaN(date.getTime())) return '';
    return ` el ${date.toLocaleString('es-MX')}`;
  });
}
