import { Component, EventEmitter, Output, inject, OnInit, signal, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { MaintenanceService } from '@features/dashboard/services/maintenance.service';
import { FormsModule } from '@angular/forms';

@Component({
  selector: 'app-maintenance-monitor-modal',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './maintenance-monitor-modal.component.html',
  styleUrl: './maintenance-monitor-modal.component.scss',
})
export class MaintenanceMonitorModalComponent implements OnInit {
  private maintenanceService = inject(MaintenanceService);

  @Output() onClose = new EventEmitter<void>();

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

    // 1. Filtramos por estado (PENDING vs RESOLVED)
    let result = (this.filter === 'PENDING')
      ? list.filter((t: any) => t.status !== 'RESOLVED')
      : list.filter((t: any) => t.status === 'RESOLVED');

    // 2. FILTRO DE SEGURIDAD (Nuevo) 🛡️
    // Esto elimina las filas "fantasmas" que no tienen descripción o ID válido.
    // Solo mostramos si tiene ID y (descripción O tipo de problema)
    return result.filter(t => t.id && (t.description || t.issue_type));
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
      // 1. Guardar en Base de Datos
      const now = new Date().toISOString();
      await this.maintenanceService.updateTicket(this.resolvingTicketId, {
        status: 'RESOLVED',
        solution_details: this.solutionText,
        resolved_at: now
      });

      // 2. Actualizar UI usando Signals (Forma Reactiva Correcta)
      this.tickets.update(currentList =>
        currentList.map(t => {
          if (t.id === this.resolvingTicketId) {
            // Retornamos una copia actualizada del ticket
            return {
              ...t,
              status: 'RESOLVED',
              solution_details: this.solutionText,
              resolved_at: now
            };
          }
          return t; // Retornamos el ticket sin cambios
        })
      );

      this.cancelResolution();
      alert('✅ ¡Mantenimiento registrado! El ticket se ha movido a la pestaña "Histórico".');

    } catch (error) {
      console.error(error);
      alert('Error al guardar la solución');
    } finally {
      this.isLoading = false;
    }
  }
}