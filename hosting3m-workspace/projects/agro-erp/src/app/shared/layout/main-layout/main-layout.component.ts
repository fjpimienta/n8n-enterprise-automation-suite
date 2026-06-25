import { ChangeDetectionStrategy, Component, inject, computed, OnInit, signal } from '@angular/core';
import { RouterOutlet } from '@angular/router';
import { NgClass } from '@angular/common';
import { TenantService } from 'core-auth';

import { SidebarComponent } from '../sidebar/sidebar.component';
import { HeaderComponent } from '../header/header.component';
import { AiChatComponent } from 'ui-chat';

@Component({
  selector: 'app-main-layout',
  standalone: true,
  imports: [RouterOutlet, NgClass, SidebarComponent, HeaderComponent, AiChatComponent],
  templateUrl: './main-layout.component.html',
  styleUrls: ['./main-layout.component.scss'],
  changeDetection: ChangeDetectionStrategy.OnPush
})
export class MainLayoutComponent implements OnInit {
  private tenantService = inject(TenantService);

  public currentTenant = this.tenantService.activeTenant;
  readonly showIosPrompt = signal<boolean>(false);

  // Dynamic theme injection based on active tenant metadata
  public themeClass = computed(() => {
    const tenant = this.currentTenant();
    const isAgri = tenant?.business_type === 'AGRICULTURE' || tenant?.industry?.toLowerCase().includes('agricultura');
    return isAgri ? 'theme-palm' : 'theme-cattle';
  });

  ngOnInit(): void {
    this.detectIosPlatform();
  }

  dismissIosPrompt(): void {
    this.showIosPrompt.set(false);
  }

  private detectIosPlatform(): void {
    // SSR Safe Guard: Prevents compilation or execution errors during server-side rendering
    if (typeof window === 'undefined' || !navigator) {
      return;
    }

    const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent) && !(window as any).MSStream;
    const isStandalone = window.matchMedia('(display-mode: standalone)').matches ||
      (navigator as any).standalone === true;

    // Trigger help prompt only if the user navigates from a standard iOS Safari environment
    if (isIOS && !isStandalone) {
      this.showIosPrompt.set(true);
    }
  }
}