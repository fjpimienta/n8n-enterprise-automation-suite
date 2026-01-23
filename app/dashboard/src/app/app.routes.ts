import { Routes } from '@angular/router';
import { LoginComponent } from '@admin/components/login/login.component';
import { DashboardComponent } from '@dashboard/components/dashboard/dashboard.component';
import { authGuard } from './core/auth/auth.guard';

export const routes: Routes = [
  { path: 'login', component: LoginComponent },
  { path: '', redirectTo: 'login', pathMatch: 'full' },
  {
    path: 'dashboard',
    component: DashboardComponent,
    canActivate: [authGuard]
  },
  { path: '**', redirectTo: 'login' }
];