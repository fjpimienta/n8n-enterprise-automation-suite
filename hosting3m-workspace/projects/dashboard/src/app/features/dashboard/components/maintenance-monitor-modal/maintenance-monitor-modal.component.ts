import { Component, EventEmitter, Output, inject, OnInit, signal, computed, input } from '@angular/core';
import { CommonModule } from '@angular/common';
import { MaintenanceService } from '@features/dashboard/services/maintenance.service';
import { FormsModule } from '@angular/forms';
import { HotelService } from '@features/dashboard/services/hotel.service';

@Component({
  selector: 'app-maintenance-monitor-modal',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './maintenance-monitor-modal.component.html',
  styleUrl: './maintenance-monitor-modal.component.scss',
})
export class MaintenanceMonitorModalComponent implements OnInit {
  private maintenanceService = inject(MaintenanceService);
  private hotelService = inject(HotelService);

  @Output() onClose = new EventEmitter<void>();
  targetRoomId = input<number | null>(null);

  // Signal para la lista de tickets
  tickets = signal<any[]>([]);
  isLoading = true;
  filter: 'PENDING' | 'RESOLVED' = 'PENDING';
  resolvingTicketId: number | null = null;
  solutionText: string = '';
  showError = false;

  // Signal computada para el contador (se actualiza sola)
  pendingCount = computed(() => {
    return this.tickets().filter(t =>
      t.status !== 'RESOLVED' &&      // 1. Que esté pendiente
      t.id &&                         // 2. Que tenga ID real
      (t.description || t.issue_type) // 3. Que tenga datos (descripción o tipo)
    ).length;
  });

  ngOnInit() {
    this.loadTickets();
  }

  async loadTickets() {
    this.isLoading = true;
    try {
      const allTickets = await this.maintenanceService.getTickets();
      console.log('Tickets obtenidos:', allTickets);
      // Ordenamos
      const data = allTickets.sort((a: any, b: any) => {
        const priorityVal: any = { 'CRITICAL': 3, 'NORMAL': 2, 'LOW': 1 };
        return priorityVal[b.priority] - priorityVal[a.priority];
      });

      // Guardamos en la Signal
      this.tickets.set(data);
    } catch (error) {
      console.error(error);
    } finally {
      this.isLoading = false;
    }
  }

  // Getter corregido y BLINDADO
  get filteredTickets() {
    const list = this.tickets();
    const specificRoom = this.targetRoomId();

    // Filtro base: Pendientes vs Resueltos
    let result = (this.filter === 'PENDING')
      ? list.filter((t: any) => t.status !== 'RESOLVED')
      : list.filter((t: any) => t.status === 'RESOLVED');

    // Filtro de Seguridad (Fantasmas)
    result = result.filter(t => t.id && (t.description || t.issue_type));

    // 👇 FILTRO ESPECÍFICO DE HABITACIÓN (La lógica nueva)
    if (specificRoom) {
      result = result.filter(t => t.room_id === specificRoom);
    }

    return result;
  }

  async resolveTicket(ticket: any) {
    if (!confirm('¿Confirmas que el problema ha sido solucionado?')) return;

    try {
      await this.maintenanceService.updateTicket(ticket.id, {
        status: 'RESOLVED',
        resolved_at: new Date().toISOString()
      });

      // Actualizamos la Signal de forma reactiva
      this.tickets.update(current =>
        current.map(t =>
          t.id === ticket.id
            ? { ...t, status: 'RESOLVED', resolved_at: new Date().toISOString() }
            : t
        )
      );

      alert('✅ Ticket cerrado correctamente');
    } catch (error) {
      alert('Error al actualizar');
    }
  }

  // 1. Inicia el proceso (Muestra el textarea)
  startResolution(ticket: any) {
    this.resolvingTicketId = ticket.id;
    this.solutionText = ''; // Limpia el texto anterior
  }

  // 2. Cancela el proceso
  cancelResolution() {
    this.resolvingTicketId = null;
    this.solutionText = '';
    this.showError = false;
  }

  // 3. Guarda la solución (Reemplaza al resolveTicket anterior)
  async confirmResolution() {
    if (!this.resolvingTicketId) return;
    if (!this.solutionText.trim()) {
      this.showError = true;
      return;
    }

    this.showError = false;
    this.isLoading = true;
    try {
      // 1. Guardar Solución en Ticket
      const now = new Date().toISOString();
      await this.maintenanceService.updateTicket(this.resolvingTicketId, {
        status: 'RESOLVED',
        solution_details: this.solutionText,
        resolved_at: now
      });

      // 2. ⚡ AUTOMATIZACIÓN: Buscar el ticket para obtener el room_id
      const ticket = this.tickets().find(t => t.id === this.resolvingTicketId);

      if (ticket && ticket.room_id) {
        // Cambiar estado a 'available' pero 'dirty'
        await this.hotelService.finishMaintenance(ticket.room_id);
      }

      // 3. Actualizar UI
      this.tickets.update(currentList =>
        currentList.map(t => {
          if (t.id === this.resolvingTicketId) {
            return {
              ...t,
              status: 'RESOLVED',
              solution_details: this.solutionText,
              resolved_at: now
            };
          }
          return t;
        })
      );

      this.cancelResolution();
      alert('✅ Mantenimiento finalizado. La habitación se marcó como SUCIA para limpieza.');

    } catch (error) {
      console.error(error);
      alert('Error al guardar la solución');
    } finally {
      this.isLoading = false;
    }
  }
}