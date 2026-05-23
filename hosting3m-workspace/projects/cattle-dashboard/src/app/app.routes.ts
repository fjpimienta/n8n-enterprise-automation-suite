import { Routes } from '@angular/router';
import { authGuard, roleGuard } from '@core/auth/auth.guard';
import { LoginComponent } from '@features/admin/components/login/login.component';

export const routes: Routes = [
  // 1. Ruta pública de Autenticación
  { path: 'login', component: LoginComponent },

  // 2. Rutas Privadas (Protegidas por AuthGuard y envueltas en el Layout Principal)
  {
    path: '',
    canActivate: [authGuard],
    loadComponent: () => import('./shared/layout/main-layout/main-layout.component').then(m => m.MainLayoutComponent),
    children: [
      {
        path: 'dashboard',
        loadComponent: () => import('./features/dashboard/components/main-dashboard/main-dashboard.component').then(m => m.MainDashboardComponent)
      },
      {
        path: 'dashboard',
        children: [
          { path: 'reproductivo', loadComponent: () => import('./features/dashboard/components/reproductive-dashboard/reproductive-dashboard.component').then(m => m.ReproductiveDashboardComponent) }
        ]
      },
      {
        path: 'inventario',
        loadComponent: () => import('./features/inventory/components/cattle-list/cattle-list.component').then(m => m.CattleListComponent)
      },
      {
        path: 'pesajes',
        loadComponent: () => import('./features/weighing/components/adg-alerts/adg-alerts.component').then(m => m.AdgAlertsComponent)
      },
      {
        path: 'admin',
        canActivate: [roleGuard(['ADMIN'])], // 🛡️ Protección adicional basada en roles
        loadComponent: () => import('./features/admin/components/tenant-list/tenant-list.component').then(m => m.TenantListComponent)
      },
      { path: '', redirectTo: 'dashboard', pathMatch: 'full' }
    ]
  },

  // 3. Redirección comodín (Cualquier ruta inválida cae aquí, y el AuthGuard decide si va a login o dashboard)
  { path: '**', redirectTo: 'dashboard' }
];