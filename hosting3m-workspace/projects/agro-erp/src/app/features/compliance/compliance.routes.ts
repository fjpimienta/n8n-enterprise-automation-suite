import { Routes } from '@angular/router';

export const complianceRoutes: Routes = [
  {
    path: 'upp',
    loadComponent: () =>
      import('./components/upp-compliance-list/upp-compliance-list.component').then(m => m.UppComplianceListComponent)
  },
  {
    path: 'upp/:id',
    loadComponent: () =>
      import('./components/upp-detail/upp-detail.component').then(m => m.UppDetailComponent)
  },
  { path: '', redirectTo: 'upp', pathMatch: 'full' }
];
