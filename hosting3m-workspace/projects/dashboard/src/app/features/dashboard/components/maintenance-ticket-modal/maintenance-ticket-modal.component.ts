import { Component, EventEmitter, Output, inject, input } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { MaintenanceService } from '@features/dashboard/services/maintenance';

@Component({
  selector: 'app-maintenance-ticket-modal',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './maintenance-ticket-modal.component.html',
  styleUrl: './maintenance-ticket-modal.component.scss',
})
export class MaintenanceTicketModalComponent {
  private maintenanceService = inject(MaintenanceService);

  // Inputs: Recibimos la habitación y (opcionalmente) el ID de inspección si viene de un rondín
  room = input.required<any>();
  inspectionId = input<number | null>(null); 
  
  @Output() onClose = new EventEmitter<void>();
  @Output() onSave = new EventEmitter<any>();

  isLoading = false;

  ticket = {
    issue_type: 'PLOMERIA',
    priority: 'NORMAL',
    description: ''
  };

  async saveTicket() {
    if (!this.ticket.description) return;
    
    this.isLoading = true;
    try {
      const newTicket = {
        ...this.ticket,
        room_id: this.room().id,
        inspection_id: this.inspectionId() || null
      };

      await this.maintenanceService.createTicket(newTicket);
      this.onSave.emit(newTicket);
      this.onClose.emit();
      alert('✅ Ticket de mantenimiento creado');
    } catch (error) {
      alert('Error al crear ticket');
    } finally {
      this.isLoading = false;
    }
  }
}