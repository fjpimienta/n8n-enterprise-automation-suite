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
    {
        // Lots of the active plantation: every palm role reads (EDITOR records counts from the rows);
        // create / edit / deactivate is ADMIN / OWNER inside the screen.
        path: 'lotes',
        canActivate: [palmDomainGuard],
        loadComponent: () => import('./lots/agri-lot-list.component').then(m => m.AgriLotListComponent)
    },
    {
        // Rows, counts and history of one lot (the lot id is re-validated inside the screen).
        path: 'lotes/:lotId/filas',
        canActivate: [palmDomainGuard],
        loadComponent: () => import('./rows/agri-row-list.component').then(m => m.AgriRowListComponent)
    },
    { path: '', redirectTo: 'dashboard', pathMatch: 'full' }
];
