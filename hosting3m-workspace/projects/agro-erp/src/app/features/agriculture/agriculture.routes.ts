import { Routes } from '@angular/router';

export const agricultureRoutes: Routes = [
    {
        path: 'dashboard',
        loadComponent: () => import('./dashboard/components/palm-dashboard/palm-dashboard.component').then(m => m.PalmDashboardComponent)
    },
    { path: '', redirectTo: 'dashboard', pathMatch: 'full' }
];