import { Component, EventEmitter, Input, Output, signal, OnInit, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { PhTransaction } from '@core/models/pista.types';

@Component({
  selector: 'app-checkout-modal',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './checkout-modal.component.html',
  styleUrls: ['./checkout-modal.component.css']
})
export class CheckoutModalComponent implements OnInit {
  // Recibimos los datos de la tarjeta seleccionada
  @Input({ required: true }) transaction!: PhTransaction;
  @Output() onClose = new EventEmitter<void>();
  @Output() onConfirm = new EventEmitter<any>();

  data = signal<PhTransaction>({} as PhTransaction);

  // Estados del Check-out
  zamboniApplied = signal(false);
  paymentMethod = signal<'CASH' | 'CARD'>('CASH');

  // Variables calculadas
  currentTime = '';
  minutesElapsed = 0;

  // Precio Base (Esto luego vendrá de n8n)
  PRICE_PER_SESSION = 80;

  totalAmount = computed(() => {
    // Aquí replicarías la lógica compleja de PHP si quisieras hacerlo en frontend
    // Por ahora, cobramos la sesión base. 
    return this.PRICE_PER_SESSION;
  });

  ngOnInit() {
    this.data.set(this.transaction);
    this.calculateTime();
  }

  calculateTime() {
    const now = new Date();
    this.currentTime = now.toTimeString().split(' ')[0].substring(0, 5); // HH:MM

    // Calcular diferencia
    const [startH, startM] = this.transaction.start_time.split(':').map(Number);
    const startDate = new Date();
    startDate.setHours(startH, startM, 0);

    let diffMs = now.getTime() - startDate.getTime();
    let diffMins = Math.floor(diffMs / 60000);

    this.minutesElapsed = diffMins;
  }

  toggleZamboni() {
    this.zamboniApplied.update(v => !v);
    if (this.zamboniApplied()) {
      this.minutesElapsed = Math.max(0, this.minutesElapsed - 15);
    } else {
      this.calculateTime(); // Recalcular original
    }
  }

  confirmCheckout() {
    this.onConfirm.emit({
      transactionId: this.transaction.id,
      endTime: this.currentTime + ':00', // HH:MM:SS
      finalAmount: this.totalAmount(),
      paymentMethod: this.paymentMethod(),
      zamboni: this.zamboniApplied()
    });
  }

  close() {
    this.onClose.emit();
  }
}