import { ChangeDetectionStrategy, Component, ElementRef, Injector, afterNextRender, computed, inject, input, output, signal, viewChild } from '@angular/core';
import { MT_REASON_LABEL, MtItem, ageText, issueLabel } from '../logic/maintenance';
import { StatusChipComponent } from './status-chip.component';

/**
 * One open maintenance ticket. Presentational: it never shows cost and records nothing about who reported it.
 * The only action is "Resolver falla" (two steps: ask, then confirm), offered only when the page says the role is
 * allowed (`allowed`, fail-closed default) and the ticket is plainly resolvable; the page decides what it does.
 */
@Component({
  selector: 'app-maintenance-row',
  standalone: true,
  imports: [StatusChipComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="h-mt__info">
      <span class="h-mt__number">{{ roomNumber() }}</span>
      <app-status-chip kind="reserved" [label]="type()" />
      @if (item().old) { <app-status-chip kind="maintenance" label="Antiguo" /> }
      @if (item().roomState === 'blocked') { <app-status-chip kind="maintenance" label="Bloqueada" /> }
      @if (item().roomState === 'pending') { <app-status-chip kind="cleaning" label="Con falla pendiente" /> }
      @if (item().group === 'review') { <app-status-chip kind="reserved" label="Revisar datos" /> }
    </div>
    <p class="h-mt__desc">{{ description() }}</p>
    <p class="h-mt__meta">Reportada: {{ age() }}</p>
    @if (reasons()) { <p class="h-mt__meta h-mt__meta--review">{{ reasons() }}</p> }
    @if (allowed() && item().resolvable) {
      <div class="mt-actions">
        <button #ask type="button" class="h-btn mt-btn" [disabled]="busy()" [attr.aria-expanded]="confirming()"
          [attr.aria-controls]="panelId()" [attr.aria-label]="'Resolver falla de la habitación ' + roomNumber()" (click)="toggle()">Resolver falla</button>
        @if (confirming()) {
          <div class="mt-confirm" role="group" [id]="panelId()" [attr.aria-label]="'Confirmar resolución de la falla de la habitación ' + roomNumber()"
            (keydown.escape)="cancel()">
            <p class="mt-confirm__text">¿Marcar como resuelta la falla de la habitación {{ roomNumber() }}? No se puede deshacer desde aquí.</p>
            <div class="mt-confirm__buttons">
              <button #confirmBtn type="button" class="h-btn h-btn--primary mt-btn" [disabled]="busy()" [attr.aria-busy]="busy()" (click)="confirm()">
                {{ busy() ? 'Guardando…' : 'Confirmar resolución' }}</button>
              <button type="button" class="h-btn mt-btn" [disabled]="busy()" (click)="cancel()">Cancelar</button>
            </div>
          </div>
        }
      </div>
    }`,
  // Local styles on purpose: the housekeeping classes pin their button to a grid cell, which stacked the two
  // confirmation buttons on top of each other in this row.
  styles: [`
    .mt-actions { display: grid; gap: var(--h-space-2); justify-items: start; }
    .mt-btn { min-height: 48px; }
    .mt-confirm { display: grid; gap: var(--h-space-2); padding: var(--h-space-3); border: 1px solid var(--h-border); border-radius: var(--h-radius-sm); }
    .mt-confirm__text { margin: 0; overflow-wrap: anywhere; }
    .mt-confirm__buttons { display: flex; flex-wrap: wrap; gap: var(--h-space-2); }
    @media (max-width: 599px) {
      .mt-actions, .mt-confirm { justify-items: stretch; }
      .mt-btn { width: 100%; }
      .mt-confirm__buttons { display: grid; }
    }`]
})
export class MaintenanceRowComponent {
  readonly item = input.required<MtItem>();
  /** Role permits resolving (decided by the page from the permissions table). Hidden unless true. */
  readonly allowed = input<boolean>(false);
  readonly busy = input<boolean>(false);
  readonly resolve = output<number>();
  protected readonly confirming = signal(false);
  private readonly injector = inject(Injector);
  private readonly askBtn = viewChild<ElementRef<HTMLButtonElement>>('ask');
  private readonly confirmBtn = viewChild<ElementRef<HTMLButtonElement>>('confirmBtn');
  protected readonly panelId = computed(() => `mt-confirm-${this.item().key}`);

  /** Opens or closes the confirmation. Opening moves focus to "Confirmar resolución" (keyboard users land on it). */
  protected toggle(): void {
    if (this.confirming()) { this.cancel(); return; }
    this.confirming.set(true);
    afterNextRender(() => this.confirmBtn()?.nativeElement.focus(), { injector: this.injector });
  }

  /** Closes the confirmation and returns focus to "Resolver falla". */
  protected cancel(): void {
    this.confirming.set(false);
    afterNextRender(() => this.askBtn()?.nativeElement.focus(), { injector: this.injector });
  }

  protected confirm(): void {
    const id = this.item().ticket.id;
    this.confirming.set(false);
    if (id !== null) this.resolve.emit(id);
  }
  protected readonly roomNumber = computed(() => this.item().room?.number ?? '—');
  protected readonly type = computed(() => issueLabel(this.item().ticket.issueType));
  protected readonly description = computed(() => this.item().ticket.description || 'Sin descripción');
  protected readonly age = computed(() => ageText(this.item().ageDays));
  protected readonly reasons = computed(() => this.item().reasons.map(r => MT_REASON_LABEL[r]).join(' · '));
}
