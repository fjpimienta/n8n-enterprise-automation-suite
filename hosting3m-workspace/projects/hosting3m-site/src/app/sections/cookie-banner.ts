import { ChangeDetectionStrategy, Component, ElementRef, effect, inject, viewChild } from '@angular/core';
import { ConsentService } from '../core/consent';

@Component({
  selector: 'app-cookie-banner',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    @if (consent.bannerOpen()) {
      <section #banner tabindex="-1" aria-label="Preferencias de cookies" class="outline-none fixed inset-x-0 bottom-0 z-50 border-t border-slate-300 bg-white p-4 shadow-lg">
        <div class="container-page flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
          <p class="max-w-3xl text-sm">
            Usamos Google Analytics para medir las visitas, solo si lo aceptas. Más información en la
            <a href="/politica-de-privacidad" class="underline">política de privacidad</a>.
          </p>
          <div class="flex gap-3">
            <button type="button" class="btn-secondary" (click)="consent.reject()">Rechazar</button>
            <button type="button" class="btn-secondary" (click)="consent.accept()">Aceptar</button>
          </div>
        </div>
      </section>
    }
  `,
})
export class CookieBanner {
  readonly consent = inject(ConsentService);
  private readonly banner = viewChild<ElementRef<HTMLElement>>('banner');

  constructor() {
    // Only when the visitor reopens it from the footer: move focus to the banner. Never on first load.
    effect(() => {
      if (this.consent.reopenCount() > 0 && this.consent.bannerOpen()) setTimeout(() => this.banner()?.nativeElement.focus());
    });
  }
}
