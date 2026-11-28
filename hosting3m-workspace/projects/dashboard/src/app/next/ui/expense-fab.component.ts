import { ChangeDetectionStrategy, Component, output } from '@angular/core';
import { HIconComponent } from '../../shared/ui/h-icon/h-icon.component';

/** Expense capture button for tablet/desktop (on mobile the bottom nav "+" does this). */
@Component({
  selector: 'app-expense-fab',
  standalone: true,
  imports: [HIconComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `<button type="button" class="h-fab-expense" aria-label="Registrar gasto" title="Registrar gasto" (click)="pressed.emit()">
    <app-h-icon name="plus" [size]="28" /></button>`
})
export class ExpenseFabComponent {
  readonly pressed = output<void>();
}
