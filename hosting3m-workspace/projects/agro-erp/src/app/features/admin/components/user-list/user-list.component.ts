import { Component, inject, signal, computed, effect } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { lastValueFrom } from 'rxjs';
import { AdminService } from '@features/admin/services/admin.service';
import { UserFormModalComponent } from '../user-form-modal/user-form-modal.component';
import { TenantService } from 'core-auth/services/tenant.service';

@Component({
  selector: 'app-user-list',
  standalone: true,
  imports: [CommonModule, FormsModule, UserFormModalComponent],
  templateUrl: './user-list.component.html',
  styleUrl: './user-list.component.css',
})
export class UserListComponent {
  public adminService = inject(AdminService);
  public tenantService = inject(TenantService);

  users = this.adminService.users;

  searchQuery = signal<string>('');
  roleFilter = signal<string>('ALL');

  filteredUsers = computed(() => {
    const q = this.searchQuery().toLowerCase();
    const role = this.roleFilter();
    return this.users().filter(u => {
      const matchesQuery = !q ||
        u.names?.toLowerCase().includes(q) ||
        u.lastname?.toLowerCase().includes(q) ||
        u.email?.toLowerCase().includes(q);
      const matchesRole = role === 'ALL' || u.role === role;
      return matchesQuery && matchesRole;
    });
  });

  isModalOpen = signal<boolean>(false);
  selectedUser = signal<any>(null);
  currentUserData = signal<any>({});

  constructor() {
    // Reacciona al cambio de tenant activo: limpia y recarga la lista
    effect(() => {
      const activeTenant = this.tenantService.activeTenant();
      if (activeTenant?.role === 'ADMIN') {
        this.adminService.users.set([]);
        this.adminService.loadUsers();
      }
    }, { allowSignalWrites: true });
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
    const tenantId = Number(this.tenantService.activeTenantId());

    if (!data.email || !data.names || !data.role) {
      alert('⚠️ Nombre, Correo y Rol son obligatorios para la trazabilidad.');
      return;
    }

    try {
      await lastValueFrom(this.adminService.saveUser(data, operation, data.email));

      await lastValueFrom(
        this.adminService.saveUserCompany(data.email, tenantId, data.role, data.is_active ?? true, operation)
      );

      alert(operation === 'insert' ? '✅ Personal registrado en la UPP' : '✅ Perfil actualizado');
      this.closeModal();
      this.adminService.loadUsers();
    } catch (error) {
      console.error('[Agro-ERP] Error transaccional:', error);
      alert('❌ Error al guardar el registro en la base de datos.');
    }
  }

  async deleteUser(user: any) {
    const name = `${user.names ?? ''} ${user.lastname ?? ''}`.trim();
    if (!confirm(`⚠️ ¿Eliminar a ${name} de la UPP? Esta acción no puede deshacerse.`)) return;

    try {
      await lastValueFrom(this.adminService.deleteUser(user.email));
      this.adminService.loadUsers();
    } catch (error) {
      console.error('[Agro-ERP] Error al eliminar usuario:', error);
      alert('❌ No se pudo eliminar el registro.');
    }
  }

  private getEmptyUser() {
    return {
      names: '', lastname: '', phone: '', email: '',
      password: '', role: 'EDITOR', is_active: true,
      tenant_id: Number(this.tenantService.activeTenantId())
    };
  }
}