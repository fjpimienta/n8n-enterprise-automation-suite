import { inject } from '@angular/core';
import { RedirectFunction, Routes } from '@angular/router';
import { authGuard, TenantService } from 'core-auth';
import { LoginComponent } from '@features/admin/components/login/login.component';
import { dashboardRouteFor } from '@shared/utils/business-domain.util';

/** Root and unknown URLs land on the dashboard of the active company's domain (palm or livestock). */
const domainHome: RedirectFunction = () => dashboardRouteFor(inject(TenantService).activeTenant());

export const routes: Routes = [
  // 1. Ruta pública de Autenticación (Permanece en el Gateway)
  { path: 'login', component: LoginComponent },

  // 2. Rutas Privadas Orquestadas (Protegidas por AuthGuard y envueltas en el Layout Principal)
  {
    path: '',
    canActivate: [authGuard],
    loadComponent: () => import('./shared/layout/main-layout/main-layout.component').then(m => m.MainLayoutComponent),
    children: [
      // 🐄 Aislamiento Ganadero (Lazy Loading del dominio completo)
      {
        path: 'ganaderia',
        loadChildren: () => import('./features/livestock/livestock.routes').then(m => m.livestockRoutes)
      },
      // 🌴 Aislamiento Agrícola (Lazy Loading del dominio completo)
      {
        path: 'agricultura',
        loadChildren: () => import('./features/agriculture/agriculture.routes').then(m => m.agricultureRoutes)
      },
      // ⚙️ Aislamiento Administrativo (Transversal)
      {
        path: 'admin',
        loadChildren: () => import('./features/admin/admin.routes').then(m => m.adminRoutes)
      },
      // 📋 Cumplimiento Normativo SENASICA-SINIIGA (solo lectura)
      {
        path: 'cumplimiento',
        loadChildren: () => import('./features/compliance/compliance.routes').then(m => m.complianceRoutes)
      },
      // Redirección por defecto si entran a la raíz: dashboard del dominio de la empresa activa
      { path: '', redirectTo: domainHome, pathMatch: 'full' }
    ]
  },

  // 3. Redirección comodín (mismo criterio de dominio)
  { path: '**', redirectTo: domainHome }
];