import { Routes } from '@angular/router';
import { authGuard, roleGuard } from 'core-auth';
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
        path: 'inventario',
        loadComponent: () => import('./features/inventory/components/cattle-list/cattle-list.component').then(m => m.CattleListComponent)
      },
      {
        path: 'pesajes',
        loadComponent: () => import('./features/weighing/components/adg-alerts/adg-alerts.component').then(m => m.AdgAlertsComponent)
      },
      {
        path: 'admin',
        canActivate: [roleGuard(['ADMIN'])],
        loadComponent: () => import('./features/admin/components/tenant-list/tenant-list.component').then(m => m.TenantListComponent)
      },
      // 🚀 NUEVA RUTA: Gestión de Personal de la UPP (Protegida)
      {
        path: 'personal',
        canActivate: [roleGuard(['ADMIN'])],
        loadComponent: () => import('./features/admin/components/user-list/user-list.component').then(m => m.UserListComponent)
      },
      { path: '', redirectTo: 'dashboard', pathMatch: 'full' }
    ]
  },

  // 3. Redirección comodín
  { path: '**', redirectTo: 'dashboard' }
];