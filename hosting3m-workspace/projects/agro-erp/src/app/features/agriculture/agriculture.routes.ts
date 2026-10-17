import { Routes } from '@angular/router';
import { palmAdminGuard, palmDomainGuard } from './guards/palm.guards';

export const agricultureRoutes: Routes = [
    {
        path: 'dashboard',
        canActivate: [palmDomainGuard],
        loadComponent: () => import('./dashboard/components/palm-dashboard/palm-dashboard.component').then(m => m.PalmDashboardComponent)
    },
    {
        // Plantation administration: ADMIN / OWNER of the active company.
        path: 'plantaciones',
        canActivate: [palmAdminGuard],
        loadComponent: () => import('./plantations/plantation-list.component').then(m => m.PlantationListComponent)
    },
    { path: '', redirectTo: 'dashboard', pathMatch: 'full' }
];
