import { Component, inject, signal, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { AdminService } from '@features/admin/services/admin.service'; // Tu servicio
import { UserFormModalComponent } from '../user-form-modal/user-form-modal.component'; // Importamos el modal

@Component({
  selector: 'app-user-list',
  standalone: true,
  imports: [CommonModule, UserFormModalComponent],
  templateUrl: './user-list.component.html',
  styleUrl: './user-list.component.css',
})
export class UserListComponent implements OnInit {
  public adminService = inject(AdminService);

  users = this.adminService.users;

  isModalOpen = signal(false);
  selectedUser = signal<any>(null);
  currentUserData = signal<any>({});

  ngOnInit() {
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

    if (!data.email || !data.names) {
      alert('Nombre y Correo son obligatorios');
      return;
    }

    try {
      await new Promise((resolve, reject) => {
        this.adminService.saveUser(data, operation, data.email).subscribe({
          next: (res) => resolve(res),
          error: (err) => reject(err)
        });
      });

      alert(operation === 'insert' ? '✅ Usuario creado' : '✅ Usuario actualizado');
      this.closeModal();
      this.adminService.loadUsers(); // Refrescar lista
    } catch (error) {
      console.error(error);
      alert('❌ Error al guardar usuario');
    }
  }

  private getEmptyUser() {
    return {
      names: '', lastname: '', phone: '',
      email: '', password: '', role: 'EDITOR'
    };
  }
}