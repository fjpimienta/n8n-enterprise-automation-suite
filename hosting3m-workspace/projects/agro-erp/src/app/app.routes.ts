import { Routes } from '@angular/router';
import { authGuard } from 'core-auth';
import { LoginComponent } from '@features/admin/components/login/login.component';

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
      // Redirección por defecto si entran a la raíz
      { path: '', redirectTo: 'ganaderia/dashboard', pathMatch: 'full' }
    ]
  },

  // 3. Redirección comodín
  { path: '**', redirectTo: 'ganaderia/dashboard' }
];