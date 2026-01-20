import { Component, output } from '@angular/core';
import { CommonModule } from '@angular/common';

@Component({
  selector: 'app-header',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './header.component.html',
  styleUrl: './header.component.css',
})
export class HeaderComponent {
  onRefresh = output<void>();
  onRefreshMain = output<void>();
  onGenerateReport = output<void>();
  onLogout = output<void>();
}
