import { CheckoutModalComponent } from '@features/operations/components/checkout-modal/checkout-modal.component';
import { Component, OnInit, PLATFORM_ID, inject, signal } from '@angular/core'; // Añade importProvidersFrom
import { IceOperationsService } from '@features/operations/services/ice-operation.service';
import { TimeOnIcePipe } from '@shared/pipes/time-on-ice-pipe';
import { LucideAngularModule } from 'lucide-angular'; // Importa los iconos
import { SkeletonComponent } from '@shared/ui/loader/skeleton/skeleton.component';
import { PhTransaction } from '@core/models/pista.types';
import { CommonModule, isPlatformBrowser } from '@angular/common';

@Component({
  selector: 'app-ice-monitor',
  standalone: true,
  imports: [
    CommonModule,
    LucideAngularModule,
    TimeOnIcePipe,
    SkeletonComponent,
    CheckoutModalComponent
  ],
  templateUrl: './ice-monitor.component.html',
  styleUrls: ['./ice-monitor.component.css']
})
export class IceMonitorComponent implements OnInit {
  public iceService = inject(IceOperationsService);
  private platformId = inject(PLATFORM_ID);
  selectedTransaction = signal<PhTransaction | null>(null);
  // Variable para guardar el timer y destruirlo después
  private refreshInterval: any;

  ngOnInit() {
    // CONDICIÓN MÁGICA: Solo ejecuta esto si es el Navegador
    if (isPlatformBrowser(this.platformId)) {

      // Carga inicial (con un pequeño delay para evitar bloqueos de hidratación)
      setTimeout(() => {
        this.refresh();
      }, 100);

      // Intervalo de 30 segundos
      this.refreshInterval = setInterval(() => {
        this.refresh();
      }, 30000);
    }
  }

  // BUENA PRÁCTICA: Limpiar el intervalo al salir de la pantalla
  ngOnDestroy() {
    if (this.refreshInterval) {
      clearInterval(this.refreshInterval);
    }
  }

  refresh() {
    this.iceService.fetchActiveSkaters();
  }
  openCheckout(skater: PhTransaction) {
    this.selectedTransaction.set(skater);
  }

  closeModal() {
    this.selectedTransaction.set(null);
  }

  handleCheckout(result: any) {
    // 1. Cerramos el modal inmediatamente para mejor UX
    this.closeModal();

    // 2. Llamamos al servicio
    this.iceService.closeSession(result).subscribe({
      next: () => {
        console.log('✅ Cobro registrado exitosamente');
        // Aquí podrías poner un Toast de éxito si tuvieras una librería de alertas
      },
      error: (err) => {
        console.error('❌ Error al cobrar:', err);
        alert('Hubo un error al guardar el cobro. Intente de nuevo.');
        // Si falla, podrías volver a abrir el modal o refrescar la lista
        this.refresh();
      }
    });
  }
}