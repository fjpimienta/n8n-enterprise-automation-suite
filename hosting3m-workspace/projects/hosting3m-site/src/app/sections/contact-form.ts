import { ChangeDetectionStrategy, Component, ElementRef, OnDestroy, effect, untracked, PLATFORM_ID, afterNextRender, computed, inject, signal, viewChild } from '@angular/core';
import { isPlatformBrowser } from '@angular/common';
import { toSignal } from '@angular/core/rxjs-interop';
import { FormControl, FormGroup, ReactiveFormsModule, Validators } from '@angular/forms';
import { ActivatedRoute } from '@angular/router';
import { CONTACT_LIMITS, CONTACT_SERVICES, ContactErrorKind, ContactService, toContactError } from '../core/contact';
import { SITE } from '../core/site.config';
import { PlansService } from '../core/plans';
import { TurnstileService } from '../core/turnstile';

const SUCCESS_FALLBACK = '¡Gracias! Hemos recibido tu mensaje.';

type Status = 'idle' | 'isSubmitting' | 'success' | 'error';

@Component({
  selector: 'app-contact-form',
  imports: [ReactiveFormsModule],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './contact-form.html',
})
export class ContactForm implements OnDestroy {
  private readonly contact = inject(ContactService);
  private readonly turnstile = inject(TurnstileService);
  private readonly catalog = inject(PlansService);
  private readonly isBrowser = isPlatformBrowser(inject(PLATFORM_ID));
  private readonly query = toSignal(inject(ActivatedRoute).queryParamMap);
  private widget: { reset(): void; remove(): void } | null = null;
  private observer: IntersectionObserver | null = null;

  readonly limits = CONTACT_LIMITS;
  /** Static services plus the labels of the public catalog (so a quote button can preselect its plan). */
  readonly services = computed(() => [...CONTACT_SERVICES, ...this.catalog.serviceLabels().filter((l) => !CONTACT_SERVICES.includes(l))]);
  readonly site = SITE;
  readonly status = signal<Status>('idle');
  readonly errorKind = signal<ContactErrorKind | null>(null);
  readonly resultMessage = signal(SUCCESS_FALLBACK);
  readonly token = signal('');
  readonly submittedOnce = signal(false);
  readonly widgetHost = viewChild<ElementRef<HTMLElement>>('widgetHost');
  readonly statusEl = viewChild<ElementRef<HTMLElement>>('statusEl');

  readonly form = new FormGroup({
    names: new FormControl('', { nonNullable: true, validators: [Validators.required, Validators.maxLength(CONTACT_LIMITS.names)] }),
    middlename: new FormControl('', { nonNullable: true, validators: [Validators.maxLength(CONTACT_LIMITS.middlename)] }),
    lastname: new FormControl('', { nonNullable: true, validators: [Validators.required, Validators.maxLength(CONTACT_LIMITS.lastname)] }),
    phone: new FormControl('', { nonNullable: true, validators: [Validators.maxLength(CONTACT_LIMITS.phone), Validators.pattern(/^$|^[+0-9()\-\s.]{7,30}$/)] }),
    email: new FormControl('', { nonNullable: true, validators: [Validators.required, Validators.maxLength(CONTACT_LIMITS.email), Validators.pattern(/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/)] }),
    service: new FormControl('', { nonNullable: true, validators: [Validators.maxLength(CONTACT_LIMITS.service)] }),
    message: new FormControl('', { nonNullable: true, validators: [Validators.required, Validators.maxLength(CONTACT_LIMITS.message)] }),
    privacy: new FormControl(false, { nonNullable: true, validators: [Validators.requiredTrue] }),
    /** Honeypot: hidden from people, must stay empty. */
    empresa: new FormControl('', { nonNullable: true }),
  });

  readonly messageLength = computed(() => this.form.controls.message.value.length);

  constructor() {
    // Re-runs when the query string or the catalog changes, so a quote button can preselect the service at any time.
    effect(() => {
      const preset = this.query()?.get('servicio');
      const allowed = this.services();
      if (this.isBrowser && preset && allowed.includes(preset)) untracked(() => this.form.controls.service.setValue(preset));
    });
    afterNextRender(() => this.observeWidget());
  }

  ngOnDestroy(): void {
    this.observer?.disconnect();
    this.widget?.remove();
  }

  showError(name: keyof typeof this.form.controls): boolean {
    const c = this.form.controls[name];
    return c.invalid && (c.touched || this.submittedOnce());
  }

  async submit(): Promise<void> {
    if (this.status() === 'isSubmitting') return; // double-submit guard
    this.submittedOnce.set(true);
    this.errorKind.set(null);
    this.form.markAllAsTouched();
    if (this.form.invalid) return;

    const value = this.form.getRawValue();
    if (value.empresa !== '') {
      // A bot filled the honeypot: pretend success and send nothing.
      this.showSuccess(SUCCESS_FALLBACK);
      return;
    }
    if (!this.token()) {
      this.status.set('error');
      this.errorKind.set('turnstile');
      return;
    }

    this.status.set('isSubmitting');
    this.contact.send(value, this.token(), this.catalog.serviceLabels()).subscribe({
      next: (mensaje) => {
        this.showSuccess(mensaje || SUCCESS_FALLBACK);
        this.widget?.reset(); // Turnstile tokens are single-use
      },
      error: (err) => {
        this.status.set('error');
        this.errorKind.set(toContactError(err).kind);
        this.widget?.reset();
        this.focusStatus();
      },
    });
  }

  private showSuccess(message: string): void {
    this.resultMessage.set(message);
    this.status.set('success');
    // Clean slate: no touched/dirty controls and no forced validation display.
    this.form.reset();
    this.form.markAsPristine();
    this.form.markAsUntouched();
    this.submittedOnce.set(false);
    this.focusStatus();
  }

  private focusStatus(): void {
    if (!this.isBrowser) return;
    setTimeout(() => {
      const el = this.statusEl()?.nativeElement;
      el?.focus();
      el?.scrollIntoView?.({ block: 'center' });
    });
  }

  private observeWidget(): void {
    const host = this.widgetHost()?.nativeElement;
    if (!this.isBrowser || !host) return;
    // Load Turnstile only when the form is about to be visible, to keep the first load light.
    this.observer = new IntersectionObserver(
      (entries) => {
        if (!entries.some((e) => e.isIntersecting)) return;
        this.observer?.disconnect();
        this.turnstile
          .render(host, { onToken: (t) => this.token.set(t), onClear: () => this.token.set('') })
          .then((w) => (this.widget = w))
          .catch(() => this.errorKind.set('turnstile'));
      },
      { rootMargin: '300px' },
    );
    this.observer.observe(host);
  }
}
