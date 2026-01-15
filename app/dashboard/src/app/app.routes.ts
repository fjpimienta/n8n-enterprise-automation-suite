import { Routes } from '@angular/router';
import { LoginComponent } from '@admin/components/login/login.component';
import { DashboardComponent } from '@dashboard/components/dashboard/dashboard.component';
import { authGuard } from './core/auth/auth.guard';

export const routes: Routes = [
  { path: 'login', component: LoginComponent },
  { path: '', redirectTo: 'login', pathMatch: 'full' }, // Redirige al inicio a /login
  {
    path: 'dashboard',
    component: DashboardComponent,
    canActivate: [authGuard] // 🔒 Aquí cerramos la puerta
  },
  { path: '**', redirectTo: 'login' } // Si escriben cualquier cosa, al login
];