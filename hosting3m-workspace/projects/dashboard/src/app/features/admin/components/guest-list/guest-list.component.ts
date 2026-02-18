import { Component, inject, signal, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { AdminService } from '@features/admin/services/admin.service';
import { GuestFormModalComponent } from '../guest-form-modal/guest-form-modal.component';

@Component({
  selector: 'app-guest-list',
  standalone: true,
  imports: [CommonModule, GuestFormModalComponent],
  templateUrl: './guest-list.component.html',
  styleUrl: './guest-list.component.css',
})
export class GuestListComponent implements OnInit {
  public adminService = inject(AdminService);

  guests = this.adminService.guests;

  isModalOpen = signal(false);
  selectedGuest = signal<any>(null);
  currentGuestData = signal<any>({});

  ngOnInit() {
    this.adminService.loadGuests();
  }

  openModal(guestToEdit: any = null) {
    if (guestToEdit) {
      this.selectedGuest.set(guestToEdit);
      this.currentGuestData.set({ ...guestToEdit });
    } else {
      this.selectedGuest.set(null);
      this.currentGuestData.set(this.getEmptyGuest());
    }
    this.isModalOpen.set(true);
  }

  closeModal() {
    this.isModalOpen.set(false);
    this.selectedGuest.set(null);
  }

  async saveGuest() {
    const data = this.currentGuestData();
    try {
      if (this.selectedGuest()) {
        await this.adminService.updateGuest(data);
        alert('✅ Huésped actualizado');
      } else {
        await this.adminService.createGuest(data);
        alert('✅ Huésped registrado');
      }

      this.closeModal();
      this.adminService.loadGuests();
    } catch (error) {
      console.error(error);
      alert('❌ Error al guardar');
    }
  }

  private getEmptyGuest() {
    return {
      full_name: '', doc_id: '', email: '', phone: '',
      country: '', city: '', state: '', notes: '',
      vip_status: false, requires_invoice: false
    };
  }
}