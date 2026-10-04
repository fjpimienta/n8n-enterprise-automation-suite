import { Routes } from '@angular/router';
import { roleGuard } from 'core-auth';
import { activeTenantRouteGuard } from './guards/active-tenant-route.guard';

export const adminRoutes: Routes = [
    {
        path: 'tenants',
        canActivate: [roleGuard(['ADMIN'])],
        loadComponent: () => import('./components/tenant-list/tenant-list.component').then(m => m.TenantListComponent)
    },
    {
        path: 'tenants/:tenantId/production-units',
        canActivate: [roleGuard(['ADMIN']), activeTenantRouteGuard],
        loadComponent: () => import('./components/production-unit-list/production-unit-list.component').then(m => m.ProductionUnitListComponent)
    },
    {
        path: 'tenants/:tenantId/production-units/:uppId/lots',
        canActivate: [roleGuard(['ADMIN']), activeTenantRouteGuard],
        loadComponent: () => import('./components/lot-list/lot-list.component').then(m => m.LotListComponent)
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
    {
        path: 'etapas-vida',
        canActivate: [roleGuard(['ADMIN'])],
        loadComponent: () => import('./components/lifestage-catalog/lifestage-catalog.component').then(m => m.LifestageCatalogComponent)
    },
    {
        path: 'autorizaciones',
        canActivate: [roleGuard(['ADMIN'])],
        loadComponent: () => import('./components/authorization-list/authorization-list.component').then(m => m.AuthorizationListComponent)
    },
    { path: '', redirectTo: 'tenants', pathMatch: 'full' }
];