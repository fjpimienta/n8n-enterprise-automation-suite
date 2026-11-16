import { inject } from '@angular/core';
import { RedirectFunction, Routes } from '@angular/router';
import { TenantService } from 'core-auth';
import { notInGraceGuard, offlineSessionGuard, pinSetupRouteGuard, unlockRouteGuard } from '@core/guards/offline-session.guard';
import { LoginComponent } from '@features/admin/components/login/login.component';
import { dashboardRouteFor } from '@shared/utils/business-domain.util';
import { livestockDomainGuard } from '@shared/guards/livestock-domain.guard';

/** Root and unknown URLs land on the dashboard of the active company's domain (palm or livestock). */
const domainHome: RedirectFunction = () => dashboardRouteFor(inject(TenantService).activeTenant());

export const routes: Routes = [
  // 1. Ruta pública de Autenticación (Permanece en el Gateway)
  { path: 'login', component: LoginComponent },

  // 1b. PIN unlock for the offline grace window (#1087, phase 1b-iii-b). Only reachable in grace.
  {
    path: 'unlock',
    canActivate: [unlockRouteGuard],
    loadComponent: () => import('./features/offline-session/components/unlock/unlock.component').then(m => m.UnlockComponent)
  },

  // 2. Rutas Privadas Orquestadas (Protegidas por AuthGuard y envueltas en el Layout Principal)
  {
    path: '',
    canActivate: [offlineSessionGuard],
    loadComponent: () => import('./shared/layout/main-layout/main-layout.component').then(m => m.MainLayoutComponent),
    children: [
      // 🐄 Aislamiento Ganadero (Lazy Loading del dominio completo)
      {
        path: 'ganaderia',
        canActivate: [livestockDomainGuard],
        loadChildren: () => import('./features/livestock/livestock.routes').then(m => m.livestockRoutes)
      },
      // 🌴 Aislamiento Agrícola (Lazy Loading del dominio completo)
      {
        path: 'agricultura',
        loadChildren: () => import('./features/agriculture/agriculture.routes').then(m => m.agricultureRoutes)
      },
      // ⚙️ Aislamiento Administrativo (Transversal)
      // PIN setup (online login only). Offered by the prompt in the layout.
      {
        path: 'seguridad/pin',
        canActivate: [pinSetupRouteGuard],
        loadComponent: () => import('./features/offline-session/components/pin-setup/pin-setup.component').then(m => m.PinSetupComponent)
      },
      // Admin screens have no offline copy: denied in grace (fail-closed).
      {
        path: 'admin',
        canActivate: [notInGraceGuard],
        loadChildren: () => import('./features/admin/admin.routes').then(m => m.adminRoutes)
      },
      // 📋 Cumplimiento Normativo SENASICA-SINIIGA (solo lectura)
      {
        path: 'cumplimiento',
        canActivate: [livestockDomainGuard],
        loadChildren: () => import('./features/compliance/compliance.routes').then(m => m.complianceRoutes)
      },
      // Redirección por defecto si entran a la raíz: dashboard del dominio de la empresa activa
      { path: '', redirectTo: domainHome, pathMatch: 'full' }
    ]
  },

  // 3. Redirección comodín (mismo criterio de dominio)
  { path: '**', redirectTo: domainHome }
];