import { ChangeDetectionStrategy, Component, OnInit, signal } from '@angular/core';
import { RouterOutlet } from '@angular/router';
import { SidebarComponent } from '../sidebar/sidebar.component';

@Component({
  selector: 'app-main-layout',
  standalone: true,
  imports: [RouterOutlet, SidebarComponent],
  templateUrl: './main-layout.component.html',
  styleUrls: ['./main-layout.component.scss'],
  changeDetection: ChangeDetectionStrategy.OnPush
})
export class MainLayoutComponent implements OnInit {
  readonly isSidebarOpen = signal<boolean>(false);
  readonly showIosPrompt = signal<boolean>(false);

  ngOnInit(): void {
    this.detectIosPlatform();
  }

  toggleSidebar(): void {
    this.isSidebarOpen.update(val => !val);
  }

  dismissIosPrompt(): void {
    this.showIosPrompt.set(false);
  }

  private detectIosPlatform(): void {
    // SSR Safe Guard (Evita errores de compilación si se renderiza del lado del servidor)
    if (typeof window === 'undefined' || !navigator) {
      return;
    }

    const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent) && !(window as any).MSStream;
    const isStandalone = window.matchMedia('(display-mode: standalone)').matches || 
                         (navigator as any).standalone === true;

    // Si es entorno Apple iOS y se está abriendo desde el navegador normal (Safari)
    if (isIOS && !isStandalone) {
      this.showIosPrompt.set(true);
    }
  }
}