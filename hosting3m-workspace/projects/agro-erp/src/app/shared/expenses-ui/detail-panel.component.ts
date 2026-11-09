import { ChangeDetectionStrategy, Component, input, output } from '@angular/core';

/** Shell of a side detail panel: title, close button and projected body/footer. Stacks below on narrow screens (parent grid). */
@Component({
  selector: 'exp-detail-panel',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  styleUrl: './expenses-ui.scss',
  styles: `
    .panel { background: var(--exp-surface); border: 1px solid var(--exp-border); border-radius: 14px; overflow: hidden; }
    header { display: flex; justify-content: space-between; align-items: center; gap: .5rem; padding: .8rem 1rem; border-bottom: 1px solid var(--exp-border); }
    h3 { font-size: 1rem; font-weight: 600; margin: 0; color: var(--exp-ink); }
    .close { min-width: 44px; min-height: 44px; border: 0; background: transparent; border-radius: 8px; cursor: pointer; color: var(--exp-ink); }
    .close:focus-visible { outline: 3px solid var(--exp-accent-strong); outline-offset: 2px; }
    .body { padding: 1rem; }
    footer { padding: .8rem 1rem; border-top: 1px solid var(--exp-border); }
  `,
  template: `
    <section class="panel" [attr.aria-label]="heading()">
      <header>
        <h3>{{ heading() }}</h3>
        <button type="button" class="close" aria-label="Cerrar detalle" (click)="closed.emit()"><i class="ti ti-x" aria-hidden="true"></i></button>
      </header>
      <div class="body"><ng-content></ng-content></div>
      <footer><ng-content select="[panelFooter]"></ng-content></footer>
    </section>
  `,
})
export class DetailPanelComponent {
  heading = input.required<string>();
  closed = output<void>();
}
