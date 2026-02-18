import { Routes } from '@angular/router';
import { PlaceholderComponent } from './shared/ui/placeholder/placeholder.component';
import { authGuard } from './core/auth/auth.guard';
import { LoginComponent } from '@features/admin/components/login/login.component';
import { DashboardComponent } from '@features/dashboard/components/dashboard/dashboard.component';
import { MainLayoutComponent } from './shared/ui/layout/main-layout/main-layout.component';
import { ReservationManagerComponent } from '@features/booking/components/reservation-manager/reservation-manager.component';
import { MaintenanceMonitorModalComponent } from '@features/dashboard/components/maintenance-monitor-modal/maintenance-monitor-modal.component';
import { GuestListComponent } from '@features/admin/components/guest-list/guest-list.component';
import { UserListComponent } from '@features/admin/components/user-list/user-list.component';
import { DailyReportModalComponent } from '@features/finance/components/daily-report-modal/daily-report-modal.component';
import { InventoryManagerComponent } from '@features/admin/components/inventory-manager/inventory-manager.component';

export const routes: Routes = [
  { path: 'login', component: LoginComponent },
  {
    path: 'dashboard',
    component: MainLayoutComponent,
    canActivate: [authGuard],
    children: [
      { path: '', component: DashboardComponent },
      // El resto usa el Placeholder
      { path: 'mantenimiento', component: MaintenanceMonitorModalComponent },
      { path: 'reservas', component: ReservationManagerComponent },
      { path: 'huespedes', component: GuestListComponent },
      { path: 'personal', component: UserListComponent },
      { path: 'inventario', component: InventoryManagerComponent },
      { path: 'finanzas', component: DailyReportModalComponent }
    ]
  },
  { path: '', redirectTo: 'dashboard', pathMatch: 'full' }, // Redirige raíz a dashboard
  { path: '**', redirectTo: 'login' }
];