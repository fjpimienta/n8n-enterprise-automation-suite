import { ChangeDetectionStrategy, Component, computed, inject } from '@angular/core';
import { toSignal } from '@angular/core/rxjs-interop';
import { NavigationEnd, Router, RouterOutlet } from '@angular/router';
import { filter, map } from 'rxjs';
import { AuthService } from 'core-auth';
import { ThemeService } from '@core/services/theme.service';
import { MainLayoutComponent } from '../../shared/ui/layout/main-layout/main-layout.component';
import { HIconComponent } from '../../shared/ui/h-icon/h-icon.component';
import { NextSidebarComponent } from '../ui/next-sidebar.component';
import { BottomNavComponent } from '../ui/bottom-nav.component';
import { ExpenseFabComponent } from '../ui/expense-fab.component';
import { buildNav, pageTitle } from '../logic/nav';
import { formatLongDate } from '../logic/es-mx';
import { ShellStateService } from './shell-state.service';

/** `next` shell. Reuses the classic layout's state (sidebar drawer, iOS install prompt) and replaces only the view. */
@Component({
  selector: 'app-shell-layout-next',
  standalone: true,
  imports: [RouterOutlet, HIconComponent, NextSidebarComponent, BottomNavComponent, ExpenseFabComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './shell-layout-next.component.html'
})
export class ShellLayoutNextComponent extends MainLayoutComponent {
  private readonly auth = inject(AuthService);
  private readonly router = inject(Router);
  private readonly shell = inject(ShellStateService);
  protected readonly theme = inject(ThemeService);

  private readonly url = toSignal(
    this.router.events.pipe(filter((e): e is NavigationEnd => e instanceof NavigationEnd), map(() => this.router.url)),
    { initialValue: this.router.url }
  );

  protected readonly title = computed(() => pageTitle(this.url()));
  protected readonly today = formatLongDate();
  protected readonly groups = computed(() => buildNav(this.auth.hasRole('ADMIN')));

  protected closeDrawer(): void { this.isSidebarOpen.set(false); }
  protected openDrawer(): void { this.isSidebarOpen.set(true); }

  protected requestExpense(): void {
    this.shell.requestExpense();
    const path = this.router.url.split(/[?#]/)[0].replace(/\/+$/, '');
    if (path !== '/dashboard') this.router.navigate(['/dashboard']);
  }

  protected logout(): void {
    this.auth.logout();
    this.router.navigate(['/login']);
    this.closeDrawer();
  }
}
