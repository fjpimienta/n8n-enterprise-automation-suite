import { ChangeDetectionStrategy, Component, inject, computed, OnInit, signal } from '@angular/core';
import { RouterOutlet } from '@angular/router';
import { NgClass } from '@angular/common';
import { TenantService } from 'core-auth';
import { OfflineSessionService } from '@core/services/offline-session.service';
import { PinSetupPromptComponent } from '@features/offline-session/components/pin-setup-prompt/pin-setup-prompt.component';

import { SidebarComponent } from '../sidebar/sidebar.component';
import { HeaderComponent } from '../header/header.component';
import { AiChatComponent } from 'ui-chat';
import { LayoutService } from '@shared/services/layout.service';
import { ToastContainerComponent } from '@shared/components/toast-container/toast-container.component';
import { themeClassFor } from '@shared/utils/business-domain.util';

@Component({
  selector: 'app-main-layout',
  standalone: true,
  imports: [RouterOutlet, NgClass, SidebarComponent, HeaderComponent, AiChatComponent, ToastContainerComponent, PinSetupPromptComponent],
  templateUrl: './main-layout.component.html',
  styleUrls: ['./main-layout.component.scss'],
  changeDetection: ChangeDetectionStrategy.OnPush
})
export class MainLayoutComponent implements OnInit {
  private tenantService = inject(TenantService);
  public layoutService = inject(LayoutService);
  private session = inject(OfflineSessionService);

  /** Dormant without offlineGraceMs (production): the PIN prompt is not mounted at all. */
  readonly graceEnabled = this.session.graceEnabled;

  /** The chat calls the API, which is blocked in grace. */
  readonly inGrace = computed(() => this.session.state() === 'grace');

  public currentTenant = this.tenantService.activeTenant;
  readonly showIosPrompt = signal<boolean>(false);

  // Dynamic theme injection based on the active company's business domain
  public themeClass = computed(() => themeClassFor(this.currentTenant()));

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