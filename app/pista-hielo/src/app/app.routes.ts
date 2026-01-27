import { Routes } from '@angular/router';
import { LoginComponent } from './features/admin/components/login/login.component';
import { authGuard } from '@core/auth/guards/auth-guard';
import { MainLayoutComponent } from '@shared/layout/main-layout/main-layout.component';

export const routes: Routes = [
  // 1. Ruta Pública (Sin Layout, pantalla completa)
  { path: 'login', component: LoginComponent },

  // 2. Rutas Protegidas (DENTRO DEL MAIN LAYOUT)
  {
    path: '',
    component: MainLayoutComponent, // <--- El Padre de Todo
    canActivate: [authGuard],
    children: [
      // Redirección inicial
      { path: '', redirectTo: 'operations/monitor', pathMatch: 'full' },

      // OPERACIONES
      {
        path: 'operations',
        children: [
          { path: 'monitor', loadComponent: () => import('./features/operations/components/ice-monitor/ice-monitor.component').then(m => m.IceMonitorComponent) },
          { path: 'entry', loadComponent: () => import('./features/operations/components/entry-form/entry-form.component').then(m => m.EntryFormComponent) },
        ]
      },

      // ADMIN
      {
        path: 'admin',
        children: [
          { path: 'shift-report', loadComponent: () => import('./features/admin/components/shift-report/shift-report.component').then(m => m.ShiftReportComponent) },
          { path: 'clients', loadComponent: () => import('./features/admin/components/client-list/client-list').then(m => m.ClientList) },
        ]
      }
    ]
  },

  // Fallback
  { path: '**', redirectTo: 'login' }
];