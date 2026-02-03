import { CheckoutModalComponent } from '@features/operations/components/checkout-modal/checkout-modal.component';
import { Component, OnInit, OnDestroy, PLATFORM_ID, inject, signal, effect } from '@angular/core';
import { IceOperationsService } from '@features/operations/services/ice-operation.service';
import { LucideAngularModule } from 'lucide-angular';
import { SkeletonComponent } from '@shared/ui/loader/skeleton/skeleton.component';
import { CommonModule, isPlatformBrowser } from '@angular/common';
import { PhTransaction } from '@core/models/transaction.types';

// Interfaz local para visualización enriquecida
interface DisplaySkater extends PhTransaction {
  displayName: string;
  elapsedMinutes: number;
  currentCost: number;
  isOvertime: boolean;
  categoryLabel: string;
}

@Component({
  selector: 'app-ice-monitor',
  standalone: true,
  imports: [
    CommonModule,
    LucideAngularModule,
    SkeletonComponent,
    CheckoutModalComponent
  ],
  templateUrl: './ice-monitor.component.html',
  styleUrls: ['./ice-monitor.component.css']
})
export class IceMonitorComponent implements OnInit, OnDestroy {
  public iceService = inject(IceOperationsService);
  private platformId = inject(PLATFORM_ID);

  // Signal derivado con datos calculados (Nombre real, Costo, Tiempo)
  displaySkaters = signal<DisplaySkater[]>([]);

  selectedTransaction = signal<DisplaySkater | null>(null);
  private refreshInterval: any;
  private timerInterval: any;

  constructor() {
    // Cuando llegan datos nuevos del servidor (iceService.activeSkaters), recalculamos todo
    effect(() => {
      this.recalculateMetrics(this.iceService.activeSkaters());
    });
  }

  ngOnInit() {
    if (isPlatformBrowser(this.platformId)) {
      // 1. Asegurar que tenemos catálogos (para los nombres)
      this.iceService.preloadCatalogs();

      // 2. Carga inicial de tickets
      this.refresh();

      // 3. Polling al servidor (Sincronización BD) - Cada 30 seg
      this.refreshInterval = setInterval(() => {
        this.refresh();
      }, 30000);

      // 4. Reloj Local (Actualiza precios y tiempos) - Cada 1 min
      // Esto hace que el precio suba en vivo sin llamar al servidor
      this.timerInterval = setInterval(() => {
        this.recalculateMetrics(this.iceService.activeSkaters());
      }, 60000);
    }
  }

  ngOnDestroy() {
    if (this.refreshInterval) clearInterval(this.refreshInterval);
    if (this.timerInterval) clearInterval(this.timerInterval);
  }

  refresh() {
    this.iceService.fetchActiveSkaters();
  }

  /**
   * 🧠 CEREBRO DEL MONITOR
   * Convierte transacciones crudas en tarjetas inteligentes
   */
  recalculateMetrics(transactions: PhTransaction[]) {
    const now = new Date();

    const enriched = transactions.map(t => {
      // A. Calcular Tiempo Transcurrido
      // Asumimos t.start_time viene como 'HH:mm:ss' y es del día de hoy
      const [hours, mins] = t.start_time ? t.start_time.split(':').map(Number) : [0, 0];
      const startTimeDate = new Date();
      startTimeDate.setHours(hours, mins, 0);

      // Si la hora de inicio es mayor a ahora (ej. error de fecha), ajustamos
      const diffMs = now.getTime() - startTimeDate.getTime();
      const elapsed = Math.max(0, Math.floor(diffMs / 60000)); // En minutos

      // B. Calcular Costos (Usando reglas del servicio)
      const costInfo = this.iceService.calculateSessionCost(t.metadata, elapsed);

      // C. Resolver Nombre (Usando Cache)
      const realName = this.iceService.getClientName(t.client_id);

      return {
        ...t,
        displayName: realName,
        elapsedMinutes: elapsed,
        currentCost: costInfo.total,
        isOvertime: costInfo.isOvertime,
        categoryLabel: costInfo.categoryLabel
      } as DisplaySkater;
    });

    this.displaySkaters.set(enriched);
  }

  openCheckout(skater: DisplaySkater) {
    // Al abrir el checkout, pasamos el objeto YA calculado
    // Esto asegura que lo que ve en el monitor es lo que se cobra
    this.selectedTransaction.set(skater);
  }

  closeModal() {
    this.selectedTransaction.set(null);
  }

  handleCheckout(result: any) {
    this.closeModal();
    this.iceService.closeSession(result).subscribe({
      next: () => {
        this.refresh(); // Actualizar lista inmediatamente
      },
      error: (err) => {
        console.error('❌ Error:', err);
        alert('Error al cobrar.');
      }
    });
  }
}