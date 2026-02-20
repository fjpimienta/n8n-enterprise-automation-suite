import { ChangeDetectionStrategy, Component, input, output } from '@angular/core';

@Component({
  selector: 'app-header',
  standalone: true,
  imports: [],
  templateUrl: './header.component.html',
  styleUrl: './header.component.css',
  changeDetection: ChangeDetectionStrategy.OnPush
})
export class HeaderComponent {
  isAdmin = input.required<boolean>();
  currentTheme = input.required<'light' | 'dark'>();

  onRefresh = output<void>();
  onRefreshMain = output<void>();
  onGenerateReport = output<void>();
  onLogout = output<void>();
  onOpenMaintenance = output<void>();
  onThemeToggle = output<void>();
}
