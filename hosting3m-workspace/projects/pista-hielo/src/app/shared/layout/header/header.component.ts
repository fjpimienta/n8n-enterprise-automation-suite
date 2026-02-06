import { Component, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ThemeService } from '@core/services/theme.service';
import { RouterModule } from '@angular/router';
import { LayoutService } from '@shared/services/layout.service';

@Component({
  selector: 'app-header',
  standalone: true,
  imports: [CommonModule, RouterModule],
  templateUrl: './header.component.html',
  styleUrls: ['./header.component.css']
})
export class HeaderComponent {
  public layoutService = inject(LayoutService);
  public themeService = inject(ThemeService);

  toggleMobile() {
    this.layoutService.mobileMenuOpen.update(v => !v);
  }
}