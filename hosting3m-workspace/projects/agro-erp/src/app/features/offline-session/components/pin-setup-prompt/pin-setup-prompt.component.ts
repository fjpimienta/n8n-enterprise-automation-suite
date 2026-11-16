import { ChangeDetectionStrategy, Component, OnInit, inject, signal } from '@angular/core';
import { RouterLink, Router, NavigationEnd } from '@angular/router';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { filter } from 'rxjs';
import { PinLockService } from '@core/services/pin-lock.service';
import { OfflineSessionService } from '@core/services/offline-session.service';

/**
 * Dismissible prompt in the main layout, shown after an online login when the user has no PIN record.
 * Dismissing it leaves grace unusable for this user (no record = login required when the session
 * expires). The dismissal is in memory, so the prompt returns on the next app start.
 */
@Component({
  selector: 'app-pin-setup-prompt',
  standalone: true,
  imports: [RouterLink],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    @if (visible()) {
      <div class="alert alert-info d-print-none mb-3" role="region" aria-label="Crear PIN sin conexión">
        <div class="d-flex flex-wrap align-items-center gap-2">
          <div class="flex-fill">
            Crea un PIN de 6 dígitos para usar la app sin conexión cuando la sesión venza.
            <strong>Si lo descartas</strong>, cuando venza la sesión tendrás que iniciar sesión en línea.
          </div>
          <a class="btn btn-sm btn-primary" routerLink="/seguridad/pin">Crear PIN</a>
          <button type="button" class="btn btn-sm btn-outline-secondary" (click)="dismiss()">Ahora no</button>
        </div>
      </div>
    }
  `,
})
export class PinSetupPromptComponent implements OnInit {
  private readonly pinLock = inject(PinLockService);
  private readonly session = inject(OfflineSessionService);
  private readonly router = inject(Router);

  readonly visible = signal(false);
  private dismissed = false;

  ngOnInit(): void {
    void this.check();
    this.router.events
      .pipe(filter((e): e is NavigationEnd => e instanceof NavigationEnd), takeUntilDestroyed())
      .subscribe(() => void this.check());
  }

  dismiss(): void {
    this.dismissed = true;
    this.visible.set(false);
  }

  private async check(): Promise<void> {
    if (this.dismissed || this.session.readState() !== 'valid' || !this.session.online()) {
      this.visible.set(false);
      return;
    }
    const has = await this.pinLock.hasRecord();
    if (this.dismissed) return;
    this.visible.set(!has && this.session.readState() === 'valid');
  }
}
