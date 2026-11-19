import { Routes } from '@angular/router';

export const livestockRoutes: Routes = [
    {
        path: 'dashboard',
        loadComponent: () => import('./dashboard/components/main-dashboard/main-dashboard.component').then(m => m.MainDashboardComponent)
    },
    {
        path: 'inventario',
        loadComponent: () => import('./inventory/components/cattle-list/cattle-list.component').then(m => m.CattleListComponent)
    },
    {
        path: 'palpaciones',
        loadComponent: () => import('./palpations/components/palpation-report-page/palpation-report-page.component').then(m => m.PalpationReportPageComponent)
    },
    {
        path: 'pesajes',
        loadComponent: () => import('./weighing/components/adg-alerts/adg-alerts.component').then(m => m.AdgAlertsComponent)
    },
    { path: '', redirectTo: 'dashboard', pathMatch: 'full' }
];