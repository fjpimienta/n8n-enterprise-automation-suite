import { Routes } from '@angular/router';

export const routes: Routes = [
  {
    // El Layout Principal envuelve la navegación
    path: '',
    loadComponent: () => import('./shared/layout/main-layout/main-layout.component').then(m => m.MainLayoutComponent),
    children: [
      { path: '', redirectTo: 'dashboard', pathMatch: 'full' },
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
        loadComponent: () => import('./features/admin/components/tenant-list/tenant-list.component').then(m => m.TenantListComponent)
      }
    ]
  },
  { path: '**', redirectTo: 'dashboard' }
];