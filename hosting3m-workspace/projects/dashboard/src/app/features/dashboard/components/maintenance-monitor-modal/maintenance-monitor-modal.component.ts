import { Component, inject, OnInit, signal, computed, input, output } from '@angular/core';
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

  targetRoomId = input<number | null>(null);

  tickets = signal<any[]>([]);
  isLoading = true;
  filter: 'PENDING' | 'RESOLVED' = 'PENDING';
  resolvingTicketId: number | null = null;
  solutionText: string = '';
  showError = false;

  pendingCount = computed(() => {
    return this.tickets().filter(t =>
      t.status !== 'RESOLVED' &&
      t.id &&
      (t.description || t.issue_type)
    ).length;
  });

  // 1. Declaramos el evento para gritarle al Dashboard
  onResolved = output<void>();
  // 2. Busca tu función que se ejecuta al darle "Resolver" al ticket
  async resolveTicket(ticket: any) {
    try {
      // ... (Tu código actual que actualiza el ticket a RESOLVED en n8n) ...

      // 3. Forzamos que la habitación pase directamente a LIMPIA y DISPONIBLE
      await this.hotelService.finishMaintenance(ticket.room_id);

      // 4. Le avisamos al Dashboard que ya terminamos
      this.onResolved.emit();

    } catch (error) {
      console.error(error);
      alert('Error al resolver el ticket');
    }
  }

  ngOnInit() {
    this.loadTickets();
  }

  async loadTickets() {
    this.isLoading = true;
    try {
      const allTickets = await this.maintenanceService.getTickets();
      const data = allTickets.sort((a: any, b: any) => {
        const priorityVal: any = { 'CRITICAL': 3, 'NORMAL': 2, 'LOW': 1 };
        return (priorityVal[b.priority] || 0) - (priorityVal[a.priority] || 0);
      });

      this.tickets.set(data);
    } catch (error) {
      console.error('Error cargando tickets:', error);
    } finally {
      this.isLoading = false;
    }
  }

  get filteredTickets() {
    const list = this.tickets();
    const specificRoom = this.targetRoomId();

    let result = (this.filter === 'PENDING')
      ? list.filter((t: any) => t.status !== 'RESOLVED')
      : list.filter((t: any) => t.status === 'RESOLVED');

    result = result.filter(t => t.id && (t.description || t.issue_type));

    if (specificRoom) {
      result = result.filter(t => t.room_id === specificRoom);
    }

    return result;
  }

  startResolution(ticket: any) {
    this.resolvingTicketId = ticket.id;
    this.solutionText = '';
  }

  cancelResolution() {
    this.resolvingTicketId = null;
    this.solutionText = '';
    this.showError = false;
  }

  // (AQUÍ BORRASTE LA FUNCIÓN resolveTicket QUE HABÍAMOS PEGADO ANTES)

  async confirmResolution() {
    if (!this.resolvingTicketId) return;
    if (!this.solutionText.trim()) {
      this.showError = true;
      return;
    }

    this.showError = false;
    this.isLoading = true;
    try {
      const now = new Date().toISOString();

      // 1. Guarda en BD el ticket resuelto
      await this.maintenanceService.updateTicket(this.resolvingTicketId, {
        status: 'RESOLVED',
        solution_details: this.solutionText,
        resolved_at: now
      });

      // 2. Pasa la habitación a LIMPIA y DISPONIBLE
      const ticket = this.tickets().find(t => t.id === this.resolvingTicketId);
      if (ticket && ticket.room_id) {
        await this.hotelService.finishMaintenance(ticket.room_id);
      }

      // 3. Actualiza la lista interna temporalmente
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

      // 🚀 4. ¡AQUÍ ESTÁ LA SOLUCIÓN! Le gritamos al Dashboard que ya terminamos
      this.onResolved.emit();

    } catch (error) {
      console.error(error);
      alert('Error al resolver el ticket. Intente nuevamente.');
    } finally {
      this.isLoading = false;
    }
  }
}