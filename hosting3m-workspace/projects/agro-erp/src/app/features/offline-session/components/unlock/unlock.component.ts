import { ChangeDetectionStrategy, Component, OnInit, computed, inject, signal } from '@angular/core';
import { Router } from '@angular/router';
import { AuthService } from 'core-auth';
import { PinLockService, PinVerifyResult } from '@core/services/pin-lock.service';
import { OfflineSessionService } from '@core/services/offline-session.service';
import { PIN_LENGTH } from '@core/utils/pin-policy.util';

/**
 * PIN screen shown in `'grace'` until the PIN is verified (#1087, phase 1b-iii-b). Offline-safe: it
 * makes no HTTP call. "Iniciar sesión" is offered only online, and it logs out first, which also
 * clears the cache and the PIN records.
 */
@Component({
  selector: 'app-unlock',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="page page-center">
      <div class="container container-tight py-4">
        <div class="card card-md">
          <div class="card-body">
            <h2 class="h3 text-center mb-2">Sesión vencida</h2>
            <p class="text-muted text-center">
              Estás viendo la copia guardada en este dispositivo, sin conexión. Los cambios no se guardarán.
            </p>

            @if (hasRecord() === null) {
              <p class="text-center text-muted">Cargando…</p>
            } @else if (hasRecord()) {
              <form (submit)="submit($event)">
                <label class="form-label" for="unlock-pin">PIN de {{ pinLength }} dígitos</label>
                <input id="unlock-pin" class="form-control form-control-lg text-center" type="password"
                  inputmode="numeric" autocomplete="off" [maxLength]="pinLength" [value]="pin()"
                  [disabled]="busy()" (input)="onInput($event)" />
                @if (remaining() !== null) {
                  <div class="form-hint">Intentos restantes: {{ remaining() }}</div>
                }
                <button type="submit" class="btn btn-primary w-100 mt-3" [disabled]="!canSubmit()">Desbloquear</button>
              </form>
            } @else {
              <p class="text-center">
                No hay PIN configurado en este dispositivo. Inicia sesión en línea para seguir usando la copia sin conexión.
              </p>
            }

            @if (message()) {
              <div class="alert alert-warning mt-3" role="alert">{{ message() }}</div>
            }

            @if (online()) {
              <button type="button" class="btn btn-outline-secondary w-100 mt-3" (click)="signInOnline()">
                Iniciar sesión
              </button>
              <p class="small text-muted text-center mt-2">
                Si el inicio de sesión falla, tu copia y tu PIN se conservan. Si entras con <strong>otro usuario</strong>,
                la copia de este dispositivo se borrará.
              </p>
            } @else {
              <p class="small text-muted text-center mt-3">
                Sin conexión: el inicio de sesión en línea estará disponible cuando vuelva la conexión.
              </p>
            }
          </div>
        </div>
      </div>
    </div>
  `,
})
export class UnlockComponent implements OnInit {
  private readonly pinLock = inject(PinLockService);
  private readonly session = inject(OfflineSessionService);
  private readonly auth = inject(AuthService);
  private readonly router = inject(Router);

  readonly pinLength = PIN_LENGTH;
  readonly online = this.session.online;
  /** `null` while loading, then whether a usable PIN record exists for this session user. */
  readonly hasRecord = signal<boolean | null>(null);
  readonly remaining = signal<number | null>(null);
  readonly busy = signal(false);
  readonly message = signal('');
  readonly pin = signal('');
  readonly canSubmit = computed(() => this.pin().length === PIN_LENGTH && !this.busy());

  async ngOnInit(): Promise<void> {
    const has = await this.pinLock.hasRecord();
    this.hasRecord.set(has);
    this.remaining.set(has ? await this.pinLock.remainingAttempts() : null);
  }

  onInput(event: Event): void {
    const input = event.target as HTMLInputElement;
    const digits = input.value.replace(/\D/g, '').slice(0, PIN_LENGTH);
    input.value = digits;
    this.pin.set(digits);
  }

  async submit(event: Event): Promise<void> {
    event.preventDefault();
    if (!this.canSubmit()) return;
    this.busy.set(true);
    const candidate = this.pin();
    this.pin.set('');
    const result = await this.pinLock.verify(candidate);
    this.busy.set(false);
    this.handle(result);
  }

  /**
   * Goes to the login WITHOUT logging out: a failed login must keep the offline copy and the PIN. The
   * login screen is exempt, so it never triggers a logout in grace. If a different user signs in, the
   * copy is wiped after the login succeeds (see `wireLoginIdentityWipe`).
   */
  signInOnline(): void {
    void this.router.navigateByUrl('/login');
  }

  private handle(result: PinVerifyResult): void {
    switch (result.status) {
      case 'ok':
        if (this.session.unlock()) {
          void this.router.navigateByUrl('/');
        } else {
          this.message.set('No se pudo abrir la copia sin conexión. Inicia sesión en línea.');
        }
        return;
      case 'wrong':
        this.remaining.set(result.remainingAttempts);
        this.message.set(`PIN incorrecto. Te quedan ${result.remainingAttempts} intento(s).`);
        return;
      case 'locked':
        this.hasRecord.set(false);
        this.remaining.set(null);
        this.message.set('Demasiados intentos fallidos. Inicia sesión en línea para volver a usar la copia sin conexión.');
        return;
      case 'no-record':
        this.hasRecord.set(false);
        this.remaining.set(null);
        return;
      case 'not-grace':
        void this.router.navigateByUrl('/');
        return;
      case 'invalid-format':
        this.message.set(`Ingresa tus ${PIN_LENGTH} dígitos.`);
        return;
      default:
        this.message.set('No se pudo verificar el PIN en este dispositivo. Inicia sesión en línea.');
    }
  }
}
