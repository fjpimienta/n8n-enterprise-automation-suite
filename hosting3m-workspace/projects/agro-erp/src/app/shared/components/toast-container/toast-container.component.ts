import { ChangeDetectionStrategy, Component, inject } from '@angular/core';
import { ToastService, ToastType } from '@shared/services/toast.service';

const ALERT_CLASS: Record<ToastType, string> = {
  success: 'alert-success',
  error: 'alert-danger',
  info: 'alert-info'
};

/** Renders `ToastService` toasts above modals (top-right, clear of the AI chat bubble). */
@Component({
  selector: 'app-toast-container',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="position-fixed top-0 end-0 p-3 d-flex flex-column gap-2"
        style="z-index: 1090; max-width: min(420px, 100vw);" aria-live="polite" aria-atomic="false">
      @for (toast of toastService.toasts(); track toast.id) {
      <div class="alert alert-dismissible shadow mb-0" [class]="alertClass(toast.type)"
          [attr.role]="toast.type === 'error' ? 'alert' : 'status'">
        <div>{{ toast.text }}</div>
        <button type="button" class="btn-close" aria-label="Cerrar" (click)="toastService.dismiss(toast.id)"></button>
      </div>
      }
    </div>
  `
})
export class ToastContainerComponent {
  public toastService = inject(ToastService);

  public alertClass(type: ToastType): string {
    return ALERT_CLASS[type];
  }
}
