import { Component, EventEmitter, Output, input, inject, signal, computed, effect } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { IceOperationsService } from '@features/operations/services/ice-operation.service';
import { PhTransaction } from '@core/models/transaction.types';
import { LucideAngularModule } from 'lucide-angular';

@Component({
  selector: 'app-checkout-modal',
  standalone: true,
  imports: [
    CommonModule,
    FormsModule,
    LucideAngularModule
  ],
  templateUrl: './checkout-modal.component.html',
  styles: [`
    .modal-blur {
      backdrop-filter: blur(4px);
      background-color: rgba(0,0,0,0.5);
      display: block; 
      opacity: 1;
    }
    .cursor-pointer { cursor: pointer; }
    .card-active { border: 2px solid #206bc4; background-color: rgba(32, 107, 196, 0.05); }
  `]
})
export class CheckoutModalComponent {
  private iceService = inject(IceOperationsService);

  // Entrada de datos (Signal)
  data = input.required<PhTransaction>({ alias: 'transaction' });

  @Output() onClose = new EventEmitter<void>();
  @Output() onConfirm = new EventEmitter<any>();

  // --- ESTADOS REACTIVOS ---
  zamboniApplied = signal(false);
  paymentMethod = signal<'CASH' | 'CARD' | 'TRANSFER'>('CASH');

  // La hora de referencia "AHORA". Se actualiza sola al abrir el ticket.
  nowSignal = signal(new Date());

  constructor() {
    // EFECTO MÁGICO: Cada vez que cambia el ticket (data), actualizamos la hora "nowSignal"
    effect(() => {
      const _ = this.data(); // Leemos data para crear dependencia
      this.nowSignal.set(new Date()); // ¡PUM! Hora fresca
    }, { allowSignalWrites: true });
  }

  // --- CÁLCULOS AUTOMÁTICOS (COMPUTED) ---

  // 1. Hora actual formateada (para mostrar en pantalla)
  currentTime = computed(() => {
    return this.nowSignal().toTimeString().substring(0, 5);
  });

  // 2. Minutos Reales Transcurridos (Con lógica anti-error de medianoche)
  minutesElapsed = computed(() => {
    const tx = this.data();
    const now = this.nowSignal();

    // a) Construir fecha de inicio segura
    let startDate: Date;
    if (tx.transaction_date && tx.start_time) {
      // Intentar usar la fecha real de la BD
      const datePart = tx.transaction_date.split('T')[0];
      startDate = new Date(`${datePart}T${tx.start_time}`);
    } else {
      // Fallback: Asumir hoy
      const [h, m] = (tx.start_time || '00:00').split(':').map(Number);
      startDate = new Date();
      startDate.setHours(h, m, 0, 0);
    }

    // b) Corrección de Medianoche (Si inicio > ahora, fue ayer)
    if (startDate > now) {
      startDate.setDate(startDate.getDate() - 1);
    }

    // c) Calcular diferencia
    const diffMs = now.getTime() - startDate.getTime();
    return Math.max(0, Math.floor(diffMs / 60000));
  });

  // 3. Minutos Finales (Aplicando Zamboni)
  finalMinutes = computed(() => {
    const raw = this.minutesElapsed();
    const discount = this.zamboniApplied() ? 15 : 0; // Descuenta 15 min
    return Math.max(0, raw - discount);
  });

  // 4. Monto a Pagar (Consultando al servicio de precios)
  finalAmount = computed(() => {
    const minutes = this.finalMinutes();
    const metadata = this.data().metadata;

    // Calculamos usando el servicio centralizado
    const costInfo = this.iceService.calculateSessionCost(metadata, minutes);
    return costInfo.total;
  });

  // --- MÉTODOS PÚBLICOS ---

  toggleZamboni() {
    this.zamboniApplied.update(v => !v);
  }

  setPaymentMethod(method: 'CASH' | 'CARD' | 'TRANSFER') {
    this.paymentMethod.set(method);
  }

  confirmCheckout() {
    const payload = {
      transactionId: this.data().id,
      endTime: this.currentTime() + ':00', // Usamos el valor del computed
      finalAmount: this.finalAmount(),
      paymentMethod: this.paymentMethod(),
      zamboni: this.zamboniApplied()
    };
    this.onConfirm.emit(payload);
  }

  close() {
    this.onClose.emit();
  }
}