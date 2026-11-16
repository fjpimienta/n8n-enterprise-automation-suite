import { ChangeDetectionStrategy, Component, computed, inject, signal } from '@angular/core';
import { Router } from '@angular/router';
import { PinCreateResult, PinLockService } from '@core/services/pin-lock.service';
import { OfflineSessionService } from '@core/services/offline-session.service';
import { PIN_LENGTH } from '@core/utils/pin-policy.util';

/** Creates the offline PIN. Only in a valid session while online (guarded by `pinSetupRouteGuard`). */
@Component({
  selector: 'app-pin-setup',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="card">
      <div class="card-body">
        <h2 class="h3 mb-2">Crear PIN para uso sin conexión</h2>
        <p class="text-muted">
          Con un PIN de {{ pinLength }} dígitos podrás abrir la copia guardada cuando la sesión venza y no haya conexión.
          El PIN no se guarda: solo una huella derivada. La copia de datos en este dispositivo no está cifrada;
          quien tenga acceso al dispositivo puede verla.
        </p>
        @if (!online()) {
          <div class="alert alert-warning" role="status">Necesitas conexión para crear el PIN.</div>
        }
        <form (submit)="submit($event)">
          <div class="row g-3">
            <div class="col-md-6">
              <label class="form-label" for="pin-new">PIN nuevo</label>
              <input id="pin-new" class="form-control" type="password" inputmode="numeric" autocomplete="new-password"
                [maxLength]="pinLength" [value]="pin()" (input)="pin.set(digitsOf($event))" [disabled]="busy()" />
            </div>
            <div class="col-md-6">
              <label class="form-label" for="pin-confirm">Confirma el PIN</label>
              <input id="pin-confirm" class="form-control" type="password" inputmode="numeric" autocomplete="new-password"
                [maxLength]="pinLength" [value]="confirm()" (input)="confirm.set(digitsOf($event))" [disabled]="busy()" />
            </div>
          </div>
          @if (message()) {
            <div class="alert alert-warning mt-3" role="alert">{{ message() }}</div>
          }
          <div class="d-flex gap-2 mt-4">
            <button type="submit" class="btn btn-primary" [disabled]="!canSubmit()">Guardar PIN</button>
            <button type="button" class="btn btn-outline-secondary" (click)="cancel()">Ahora no</button>
          </div>
        </form>
      </div>
    </div>
  `,
})
export class PinSetupComponent {
  private readonly pinLock = inject(PinLockService);
  private readonly session = inject(OfflineSessionService);
  private readonly router = inject(Router);

  readonly pinLength = PIN_LENGTH;
  readonly online = this.session.online;
  readonly pin = signal('');
  readonly confirm = signal('');
  readonly busy = signal(false);
  readonly message = signal('');
  readonly canSubmit = computed(() =>
    this.online() && !this.busy() && this.pin().length === PIN_LENGTH && this.confirm().length === PIN_LENGTH);

  digitsOf(event: Event): string {
    const input = event.target as HTMLInputElement;
    const digits = input.value.replace(/\D/g, '').slice(0, PIN_LENGTH);
    input.value = digits;
    return digits;
  }

  async submit(event: Event): Promise<void> {
    event.preventDefault();
    if (!this.canSubmit()) return;
    if (this.pin() !== this.confirm()) {
      this.message.set('Los PIN no coinciden.');
      return;
    }
    this.busy.set(true);
    const result = await this.pinLock.createPin(this.pin());
    this.busy.set(false);
    this.pin.set('');
    this.confirm.set('');
    if (result === 'created') {
      void this.router.navigateByUrl('/');
      return;
    }
    this.message.set(messageFor(result));
  }

  cancel(): void {
    void this.router.navigateByUrl('/');
  }
}

function messageFor(result: PinCreateResult): string {
  switch (result) {
    case 'invalid-format': return `El PIN debe tener exactamente ${PIN_LENGTH} dígitos.`;
    case 'trivial': return 'Elige un PIN menos predecible: evita números repetidos o en secuencia.';
    case 'offline': return 'Necesitas conexión para crear el PIN.';
    case 'not-valid-session': return 'Inicia sesión en línea para crear el PIN.';
    case 'no-scope': return 'No se pudo identificar la sesión. Inicia sesión de nuevo.';
    default: return 'No se pudo guardar el PIN en este dispositivo.';
  }
}
