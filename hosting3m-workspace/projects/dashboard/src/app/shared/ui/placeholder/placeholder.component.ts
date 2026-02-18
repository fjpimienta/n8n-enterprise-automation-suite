import { Component, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { Router } from '@angular/router';

@Component({
  selector: 'app-placeholder',
  standalone: true,
  imports: [CommonModule],
  template: `
    <div style="padding: 2rem; color: #334155; text-align: center; margin-top: 50px;">
      <i style="font-size: 3rem; margin-bottom: 1rem; display: block;">🚧</i>
      <h1 style="font-size: 1.5rem; font-weight: 700;">Módulo en Construcción</h1>
      <p style="font-size: 1rem; margin-top: 0.5rem;">Ruta actual: <code style="background: #e2e8f0; padding: 4px; border-radius: 4px;">{{ router.url }}</code></p>
    </div>
  `
})
export class PlaceholderComponent {
  router = inject(Router);
}