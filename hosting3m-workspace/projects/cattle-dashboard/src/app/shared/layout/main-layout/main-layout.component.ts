import { Component, inject, signal, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterModule } from '@angular/router';
import { SidebarComponent } from '../sidebar/sidebar.component';
import { HeaderComponent } from '../header/header.component';
import { LayoutService } from '@shared/services/layout.service';
import { AiChatComponent } from 'ui-chat';

@Component({
  selector: 'app-main-layout',
  standalone: true,
  imports: [CommonModule, RouterModule, SidebarComponent, HeaderComponent, AiChatComponent],
  templateUrl: './main-layout.component.html',
  styleUrl: './main-layout.component.scss' // <-- Corregido a singular[cite: 11]
})
export class MainLayoutComponent {
  public layoutService = inject(LayoutService);

  public cattleList = signal<any[]>([]);
  public totalHeads = computed(() => this.cattleList().length);
  public averageAdg = computed(() => '0.850');
  public criticalAlerts = computed(() => 0);

  constructor() {
    this.cattleList.set([]);
  }
}