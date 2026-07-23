import { Routes } from '@angular/router';
import { roleGuard } from 'core-auth';

export const adminRoutes: Routes = [
    {
        path: 'tenants',
        canActivate: [roleGuard(['ADMIN'])],
        loadComponent: () => import('./components/tenant-list/tenant-list.component').then(m => m.TenantListComponent)
    },
    {
        path: 'personal',
        canActivate: [roleGuard(['ADMIN'])],
        loadComponent: () => import('./components/user-list/user-list.component').then(m => m.UserListComponent)
    },
    {
        path: 'razas',
        canActivate: [roleGuard(['ADMIN'])],
        loadComponent: () => import('./components/breed-catalog/breed-catalog.component').then(m => m.BreedCatalogComponent)
    },
    { path: '', redirectTo: 'tenants', pathMatch: 'full' }
];