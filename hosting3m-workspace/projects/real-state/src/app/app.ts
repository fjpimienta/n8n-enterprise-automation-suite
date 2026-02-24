import { Component, signal } from '@angular/core';
import { RouterOutlet } from '@angular/router';

// 1. Importación estricta de tus Features
import { CanvasEngineComponent } from './features/viewer-3d/components/canvas-engine/canvas-engine.component';
import { UnitSidebarComponent } from './features/viewer-3d/components/unit-sidebar/unit-sidebar/unit-sidebar.component';

@Component({
  selector: 'app-root',
  standalone: true,
  // 2. INYECCIÓN CRÍTICA: Debes declarar los componentes en el arreglo 'imports'
  imports: [
    RouterOutlet, 
    CanvasEngineComponent, 
    UnitSidebarComponent
  ],
  templateUrl: './app.html',
  styleUrls: ['./app.css']
})
export class App {
  protected readonly title = signal('real-state');
}
