import { ChangeDetectionStrategy, Component, input, output } from '@angular/core';
import { RouterLink, RouterLinkActive } from '@angular/router';
import { HIconComponent } from '../../shared/ui/h-icon/h-icon.component';
import { NavGroup } from '../logic/nav';

@Component({
  selector: 'app-next-sidebar',
  standalone: true,
  imports: [RouterLink, RouterLinkActive, HIconComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="h-sidebar__brand"><app-h-icon name="building" [size]="26" /> <span>Hotel San José</span></div>
    <nav class="h-sidebar__nav" aria-label="Menú principal">
      @for (g of groups(); track g.title) {
        <div class="h-sidebar__group">{{ g.title }}</div>
        @for (l of g.links; track l.route) {
          <a class="h-sidebar__link" [routerLink]="l.route" routerLinkActive="is-active" ariaCurrentWhenActive="page"
            [routerLinkActiveOptions]="{ exact: l.route === '/dashboard' }" (click)="navigated.emit()">
            <app-h-icon [name]="l.icon" [size]="20" /> {{ l.label }}
          </a>
        }
      }
    </nav>
    <div class="h-sidebar__footer">
      <button type="button" (click)="toggleTheme.emit()">
        <app-h-icon [name]="dark() ? 'sun' : 'moon'" [size]="20" /> {{ dark() ? 'Modo claro' : 'Modo oscuro' }}
      </button>
      <button type="button" (click)="logout.emit()"><app-h-icon name="logout" [size]="20" /> Cerrar sesión</button>
    </div>`
})
export class NextSidebarComponent {
  readonly groups = input.required<NavGroup[]>();
  readonly dark = input<boolean>(false);
  readonly navigated = output<void>();
  readonly toggleTheme = output<void>();
  readonly logout = output<void>();
}
