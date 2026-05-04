import { Component, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterModule } from '@angular/router';
import { LayoutService } from '../../services/layout.service';

@Component({
  selector: 'app-sidebar',
  standalone: true,
  imports: [CommonModule, RouterModule],
  templateUrl: './sidebar.component.html',
  styleUrls: ['./sidebar.component.scss']
})
export class SidebarComponent {
  public layoutService = inject(LayoutService);

  isMobileMenuOpen = this.layoutService.mobileMenuOpen;
  isCollapsed = this.layoutService.sidebarCollapsed;

  closeMenu() {
    this.layoutService.mobileMenuOpen.set(false);
  }

  toggleCollapse() {
    this.layoutService.toggleSidebar();
  }
}