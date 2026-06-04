import { Routes } from '@angular/router';
import { UnauthorizedComponent } from './shared/ui/unauthorized/unauthorized.component';
import { LoginComponent } from '@features/admin/components/login/login.component';
import { DashboardComponent } from '@features/dashboard/components/dashboard/dashboard.component';
import { MainLayoutComponent } from './shared/ui/layout/main-layout/main-layout.component';
import { ReservationManagerComponent } from '@features/booking/components/reservation-manager/reservation-manager.component';
import { MaintenanceMonitorModalComponent } from '@features/dashboard/components/maintenance-monitor-modal/maintenance-monitor-modal.component';
import { GuestListComponent } from '@features/admin/components/guest-list/guest-list.component';
import { UserListComponent } from '@features/admin/components/user-list/user-list.component';
import { DailyReportModalComponent } from '@features/finance/components/daily-report-modal/daily-report-modal.component';
import { InventoryManagerComponent } from '@features/admin/components/inventory-manager/inventory-manager.component';

// 🚀 IMPORTAMOS LOS GUARDS DESDE LA LIBRERÍA
import { authGuard, roleGuard } from 'core-auth';

export const routes: Routes = [
  { path: 'login', component: LoginComponent },
  {
    path: 'dashboard',
    component: MainLayoutComponent,
    canActivate: [authGuard], // <-- Ahora usa el Guard blindado
    children: [
      { path: '', component: DashboardComponent },
      { path: 'mantenimiento', component: MaintenanceMonitorModalComponent },
      { path: 'reservas', component: ReservationManagerComponent },
      { path: 'huespedes', component: GuestListComponent },
      { path: 'personal', component: UserListComponent, canActivate: [roleGuard(['ADMIN'])] },
      { path: 'inventario', component: InventoryManagerComponent, canActivate: [roleGuard(['ADMIN'])] },
      { path: 'finanzas', component: DailyReportModalComponent, canActivate: [roleGuard(['ADMIN'])] }
    ]
  },
  { path: 'unauthorized', component: UnauthorizedComponent },
  { path: '', redirectTo: 'dashboard', pathMatch: 'full' },
  { path: '**', redirectTo: 'login' }
];