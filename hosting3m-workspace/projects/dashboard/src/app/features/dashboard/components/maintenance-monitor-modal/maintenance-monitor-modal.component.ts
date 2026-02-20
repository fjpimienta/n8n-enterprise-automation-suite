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
  isLoading = signal(false);
  filter = signal<'PENDING' | 'RESOLVED'>('PENDING');
  resolvingTicketId: number | null = null;
  solutionText = '';
  showError = false;

  pendingCount = computed(() => {
    return this.tickets().filter(t =>
      t.status !== 'RESOLVED' &&
      t.id &&
      (t.description || t.issue_type)
    ).length;
  });

  filteredTickets = computed(() => {
    const list = this.tickets();
    const specificRoom = this.targetRoomId();
    const currentFilter = this.filter();
    let result = currentFilter === 'PENDING'
      ? list.filter((t: any) => t.status !== 'RESOLVED')
      : list.filter((t: any) => t.status === 'RESOLVED');
    result = result.filter(t => t.id && (t.description || t.issue_type));
    if (specificRoom) {
      result = result.filter(t => t.room_id === specificRoom);
    }
    return result;
  });

  onResolved = output<void>();

  async resolveTicket(ticket: any) {
    try {
      await this.hotelService.finishMaintenance(ticket.room_id);
      this.onResolved.emit();
    } catch (error) {
      console.error(error);
      alert('Error al resolver el ticket');
    }
  }

  ngOnInit() {
    this.loadTickets();
  }

  async loadTickets(forceRefresh = false) {
    this.isLoading.set(true);
    try {
      const data = await this.maintenanceService.loadTickets(forceRefresh);
      this.tickets.set(data);
    } catch (error) {
      console.error('Error cargando tickets:', error);
    } finally {
      this.isLoading.set(false);
    }
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

  async confirmResolution() {
    if (!this.resolvingTicketId) return;
    if (!this.solutionText.trim()) {
      this.showError = true;
      return;
    }

    this.showError = false;
    this.isLoading.set(true);
    try {
      const now = new Date().toISOString();

      await this.maintenanceService.updateTicket(this.resolvingTicketId, {
        status: 'RESOLVED',
        solution_details: this.solutionText,
        resolved_at: now
      });

      const ticket = this.tickets().find(t => t.id === this.resolvingTicketId);
      if (ticket && ticket.room_id) {
        await this.hotelService.finishMaintenance(ticket.room_id);
      }

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
      this.onResolved.emit();
    } catch (error) {
      console.error(error);
      alert('Error al resolver el ticket. Intente nuevamente.');
    } finally {
      this.isLoading.set(false);
    }
  }
}
