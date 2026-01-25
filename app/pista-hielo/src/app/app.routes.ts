import { Routes } from '@angular/router';
import { IceMonitorComponent } from './features/operations/components/ice-monitor/ice-monitor';

export const routes: Routes = [
  {
    path: '',
    component: IceMonitorComponent, // Carga directa para validar diseño
  }/*,
  {
    path: 'admin',
    loadComponent: () => import('./features/admin/components/client-list/client-list').then(m => m.ClientListComponent)
  },*/
  // Más adelante aquí pondremos el path: 'login'
];