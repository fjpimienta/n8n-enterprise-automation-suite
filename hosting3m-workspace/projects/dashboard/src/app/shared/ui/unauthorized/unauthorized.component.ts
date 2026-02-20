import { Component } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterLink } from '@angular/router';

@Component({
  selector: 'app-unauthorized',
  standalone: true,
  imports: [CommonModule, RouterLink],
  template: `
    <div class="unauthorized-container">
      <div class="unauthorized-content">
        <span class="icon">403</span>
        <h1>Acceso no autorizado</h1>
        <p>No tienes permisos para acceder a esta sección.</p>
        <a routerLink="/dashboard" class="btn-back">Volver al Dashboard</a>
      </div>
    </div>
  `,
  styles: [`
    .unauthorized-container {
      display: flex;
      align-items: center;
      justify-content: center;
      min-height: 60vh;
      padding: 2rem;
    }
    .unauthorized-content {
      text-align: center;
      color: #334155;
    }
    .icon {
      display: block;
      font-size: 4rem;
      font-weight: 700;
      color: #94a3b8;
      margin-bottom: 1rem;
    }
    h1 {
      font-size: 1.5rem;
      font-weight: 700;
      margin-bottom: 0.5rem;
    }
    p {
      font-size: 1rem;
      margin-bottom: 1.5rem;
    }
    .btn-back {
      display: inline-block;
      padding: 0.5rem 1rem;
      background: #3b82f6;
      color: white;
      text-decoration: none;
      border-radius: 6px;
      font-weight: 500;
      transition: background 0.2s;
    }
    .btn-back:hover {
      background: #2563eb;
    }
  `]
})
export class UnauthorizedComponent {}
