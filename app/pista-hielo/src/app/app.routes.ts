import { Routes } from '@angular/router';
import { LoginComponent } from './features/admin/components/login/login.component';
import { authGuard } from '@core/auth/guards/auth-guard';
import { IceMonitorComponent } from '@features/operations/components/ice-monitor/ice-monitor';

export const routes: Routes = [
  // Ruta por defecto: Redirigir a Operaciones (el Guard lo frenará si no hay login)
  { path: '', redirectTo: 'operations/monitor', pathMatch: 'full' },
  
  // Ruta Pública
  { path: 'login', component: LoginComponent },

  // Rutas Protegidas (Módulo Operaciones)
  { 
    path: 'operations',
    canActivate: [authGuard], // <--- El Guardián
    children: [
      { path: 'monitor', component: IceMonitorComponent },
      // Aquí añadiremos 'entry' y 'checkout' después
    ]
  },

  // Rutas Protegidas (Módulo Admin - Lazy Loading)
  {
    path: 'admin',
    canActivate: [authGuard],
    loadComponent: () => import('./features/admin/components/client-list/client-list')
        .then(m => m.ClientList)
  }
];