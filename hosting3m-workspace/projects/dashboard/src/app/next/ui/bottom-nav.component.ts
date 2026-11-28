import { ChangeDetectionStrategy, Component, output } from '@angular/core';
import { RouterLink, RouterLinkActive } from '@angular/router';
import { HIconComponent } from '../../shared/ui/h-icon/h-icon.component';

@Component({
  selector: 'app-bottom-nav',
  standalone: true,
  imports: [RouterLink, RouterLinkActive, HIconComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  host: { class: 'h-bottomnav', role: 'navigation', 'aria-label': 'Navegación principal' },
  template: `
    <a routerLink="/dashboard" routerLinkActive="is-active" ariaCurrentWhenActive="page" [routerLinkActiveOptions]="{ exact: true }">
      <app-h-icon name="grid" [size]="22" /> Panel</a>
    <a routerLink="/dashboard/reservas" routerLinkActive="is-active" ariaCurrentWhenActive="page">
      <app-h-icon name="calendar" [size]="22" /> Reservas</a>
    <button type="button" class="h-bottomnav__plus" aria-label="Registrar gasto" (click)="expense.emit()">
      <app-h-icon name="plus" [size]="28" /></button>
    <a routerLink="/dashboard/mantenimiento" routerLinkActive="is-active" ariaCurrentWhenActive="page">
      <app-h-icon name="tool" [size]="22" /> Mantenim.</a>
    <button type="button" (click)="more.emit()"><app-h-icon name="more" [size]="22" /> Más</button>`
})
export class BottomNavComponent {
  readonly expense = output<void>();
  readonly more = output<void>();
}
