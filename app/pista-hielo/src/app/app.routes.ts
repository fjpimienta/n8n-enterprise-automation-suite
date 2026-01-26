import { Routes } from '@angular/router';
import { LoginComponent } from './features/admin/components/login/login.component';
import { authGuard } from '@core/auth/guards/auth-guard';
import { IceMonitorComponent } from '@features/operations/components/ice-monitor/ice-monitor.component';

export const routes: Routes = [
  // Ruta por defecto
  { path: '', redirectTo: 'operations/monitor', pathMatch: 'full' },

  // Ruta Pública
  { path: 'login', component: LoginComponent },

  // Rutas Protegidas (Módulo Operaciones)
  {
    path: 'operations',
    canActivate: [authGuard],
    children: [
      { path: 'monitor', component: IceMonitorComponent },
      { path: 'entry', loadComponent: () => import('./features/operations/components/entry-form/entry-form.component').then(m => m.EntryFormComponent) },
    ]
  },

  // Rutas Protegidas (Módulo Admin)
  {
    path: 'admin',
    canActivate: [authGuard],
    // 1. ELIMINAMOS el loadComponent de aquí (del padre)
    children: [
      {
        path: 'shift-report',
        loadComponent: () => import('./features/admin/components/shift-report/shift-report.component').then(m => m.ShiftReportComponent)
      },
      // 2. MOVEMOS ClientList aquí adentro como una ruta específica (ej: /admin/clients)
      {
        path: 'clients', 
        loadComponent: () => import('./features/admin/components/client-list/client-list').then(m => m.ClientList)
      }
    ]
  }
];