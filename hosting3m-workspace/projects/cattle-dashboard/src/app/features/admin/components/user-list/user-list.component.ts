import { Component, inject, signal, OnInit, effect } from '@angular/core';
import { CommonModule } from '@angular/common';
import { AdminService } from '@features/admin/services/admin.service';
import { UserFormModalComponent } from '../user-form-modal/user-form-modal.component';
import { TenantService } from 'core-auth/services/tenant.service';

@Component({
  selector: 'app-user-list',
  standalone: true,
  imports: [CommonModule, UserFormModalComponent],
  templateUrl: './user-list.component.html',
  styleUrl: './user-list.component.css',
})
export class UserListComponent implements OnInit {
  public adminService = inject(AdminService);
  public tenantService = inject(TenantService);

  // Mantenemos la reactividad delegada al servicio
  users = this.adminService.users;

  // Signals para el manejo de estado local (Lean Architecture)
  isModalOpen = signal<boolean>(false);
  selectedUser = signal<any>(null);
  currentUserData = signal<any>({});

  constructor() {
    effect(() => {
      const activeTenant = this.tenantService.activeTenant();

      if (activeTenant && activeTenant.role === 'ADMIN') {
        // 1. Limpiamos la matriz actual para forzar el re-render (Feedback visual)
        // Nota: Asegúrate de que tu servicio permita hacer .set([]) o exponga un método clearUsers()
        this.adminService.users.set([]);

        // 2. Solicitamos los datos de la nueva UPP
        this.adminService.loadUsers();
      }
    }, { allowSignalWrites: true }); // Permiso necesario en Angular 21 para escribir en un effect
  }

  ngOnInit() {
    // La carga inicial asume que el backend filtra por el tenant_id activo
    this.adminService.loadUsers();
  }

  openModal(userToEdit: any = null) {
    if (userToEdit) {
      this.selectedUser.set(userToEdit);
      this.currentUserData.set({ ...userToEdit, password: '' });
    } else {
      this.selectedUser.set(null);
      this.currentUserData.set(this.getEmptyUser());
    }
    this.isModalOpen.set(true);
  }

  closeModal() {
    this.isModalOpen.set(false);
    this.selectedUser.set(null);
  }

  async saveUser() {
    const data = this.currentUserData();
    const operation = this.selectedUser() ? 'update' : 'insert';

    if (!data.email || !data.names || !data.role) {
      alert('⚠️ Nombre, Correo y Rol son obligatorios para la trazabilidad.');
      return;
    }

    try {
      await new Promise((resolve, reject) => {
        // El tenantInterceptor inyectará el tenant_id en la petición HTTP
        this.adminService.saveUser(data, operation, data.email).subscribe({
          next: (res) => resolve(res),
          error: (err) => reject(err)
        });
      });

      alert(operation === 'insert' ? '✅ Personal registrado en la UPP' : '✅ Perfil actualizado');
      this.closeModal();
      this.adminService.loadUsers();
    } catch (error) {
      console.error('[Cattle-Dashboard] Error transaccional:', error);
      alert('❌ Error al guardar el registro en la base de datos.');
    }
  }

  private getEmptyUser() {
    return {
      names: '', lastname: '', phone: '',
      email: '', password: '', role: 'OPERADOR', is_active: true
    };
  }
}