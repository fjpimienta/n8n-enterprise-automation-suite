import { Component, inject, OnInit, OnDestroy, signal, computed, input, output, ChangeDetectionStrategy, ChangeDetectorRef } from '@angular/core';
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
  changeDetection: ChangeDetectionStrategy.OnPush
})
export class MaintenanceMonitorModalComponent implements OnInit, OnDestroy {
  private maintenanceService = inject(MaintenanceService);
  private hotelService = inject(HotelService);
  private cdr = inject(ChangeDetectorRef);

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

  /**
   * Función trackBy para optimizar el rendimiento de las iteraciones
   * Evita re-renderizar elementos que no han cambiado
   */
  trackByTicketId(index: number, ticket: any): number {
    return ticket.id || index;
  }

  onResolved = output<void>();

  async resolveTicket(ticket: any) {
    this.isLoading.set(true);
    this.cdr.markForCheck();
    try {
      await this.hotelService.finishMaintenance(ticket.room_id);
      this.onResolved.emit();
      this.cdr.markForCheck();
    } catch (error) {
      console.error('Error al resolver ticket:', error);
      alert('Error al resolver el ticket');
    } finally {
      this.isLoading.set(false);
      this.cdr.markForCheck();
    }
  }

  ngOnInit() {
    this.loadTickets();
  }

  async loadTickets(forceRefresh = false) {
    this.isLoading.set(true);
    this.cdr.markForCheck();
    try {
      const data = await this.maintenanceService.loadTickets(forceRefresh);
      this.tickets.set(data);
      this.cdr.markForCheck();
    } catch (error) {
      console.error('Error cargando tickets:', error);
    } finally {
      this.isLoading.set(false);
      this.cdr.markForCheck();
    }
  }

  startResolution(ticket: any) {
    this.resolvingTicketId = ticket.id;
    this.solutionText = '';
  }

  cancelResolution() {
    this.resetForm();
  }

  async confirmResolution() {
    if (!this.resolvingTicketId) return;
    
    // Validación robusta: verificar que la solución no esté vacía después de trim
    const trimmedSolution = this.solutionText.trim();
    if (!trimmedSolution || trimmedSolution.length < 5) {
      this.showError = true;
      this.cdr.markForCheck();
      return;
    }

    this.showError = false;
    this.isLoading.set(true);
    this.cdr.markForCheck();

    try {
      const now = new Date().toISOString();

      await this.maintenanceService.updateTicket(this.resolvingTicketId, {
        status: 'RESOLVED',
        solution_details: trimmedSolution, // Usar valor con trim
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
              solution_details: trimmedSolution,
              resolved_at: now
            };
          }
          return t;
        })
      );

      this.resetForm();
      this.onResolved.emit();
      this.cdr.markForCheck();
    } catch (error) {
      console.error('Error al resolver ticket:', error);
      alert('Error al resolver el ticket. Intente nuevamente.');
    } finally {
      this.isLoading.set(false);
      this.cdr.markForCheck();
    }
  }

  /**
   * Resetea el formulario de resolución a su estado inicial
   */
  private resetForm(): void {
    this.resolvingTicketId = null;
    this.solutionText = '';
    this.showError = false;
    this.cdr.markForCheck();
  }

  /**
   * Limpieza de recursos al destruir el componente
   */
  ngOnDestroy(): void {
    this.resetForm();
    // Los signals se limpian automáticamente, pero reseteamos estado manual
    this.tickets.set([]);
    this.isLoading.set(false);
    this.filter.set('PENDING');
  }
}
