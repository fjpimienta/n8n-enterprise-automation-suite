import { Component, EventEmitter, Output, OnInit, input, inject, signal } from '@angular/core';
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
export class CheckoutModalComponent implements OnInit {
  private iceService = inject(IceOperationsService);

  data = input.required<PhTransaction>({ alias: 'transaction' });
  @Output() onClose = new EventEmitter<void>();
  @Output() onConfirm = new EventEmitter<any>();

  // Estados
  zamboniApplied = signal(false);
  paymentMethod = signal<'CASH' | 'CARD' | 'TRANSFER'>('CASH');

  // Variables de tiempo
  public currentTime: string = '';
  public minutesElapsed: number = 0;

  // Totales Reactivos
  public finalMinutes = signal(0);
  public finalAmount = signal(0);

  ngOnInit() {
    this.initializeModal();
  }

  initializeModal() {
    const tx = this.data();
    const now = new Date();

    // 1. Mostrar hora actual formateada
    this.currentTime = now.toTimeString().substring(0, 5); // HH:mm

    // 2. CALCULAR FECHA DE INICIO REAL (Corrección del Bug)
    let startDate: Date;

    if (tx.transaction_date && tx.start_time) {
      // Si tenemos la fecha de la base de datos, la usamos.
      // Formato seguro: "2026-02-02T23:43:00"
      const datePart = tx.transaction_date.split('T')[0]; // Asegurar solo YYYY-MM-DD
      startDate = new Date(`${datePart}T${tx.start_time}`);
    } else {
      // Fallback si falta la fecha: Usamos la hora y asumimos "Hoy"
      const [h, m] = (tx.start_time || '00:00').split(':').map(Number);
      startDate = new Date();
      startDate.setHours(h, m, 0, 0);
    }

    // 3. DETECCIÓN DE CRUCE DE MEDIANOCHE (Safety Check)
    // Si la fecha de inicio calculada es MAYOR que ahora, significa que 
    // el sistema pensó que era "hoy a las 11pm" pero en realidad estamos a "mañana a las 12am".
    // Restamos 1 día a la fecha de inicio.
    if (startDate > now) {
      startDate.setDate(startDate.getDate() - 1);
    }

    // 4. Calcular diferencia real en minutos
    const diffMs = now.getTime() - startDate.getTime();
    this.minutesElapsed = Math.max(0, Math.floor(diffMs / 60000));

    // 5. Calcular totales iniciales
    this.recalculateTotals();
  }

  toggleZamboni() {
    this.zamboniApplied.update(v => !v);
    this.recalculateTotals();
  }

  setPaymentMethod(method: 'CASH' | 'CARD' | 'TRANSFER') {
    this.paymentMethod.set(method);
  }

  recalculateTotals() {
    // Aplicar descuento de tiempo (Zamboni)
    // Ahora que minutesElapsed es correcto, esto funcionará.
    const adjustedMinutes = this.zamboniApplied()
      ? Math.max(0, this.minutesElapsed - 15)
      : this.minutesElapsed;

    this.finalMinutes.set(adjustedMinutes);

    // Calcular dinero
    const costInfo = this.iceService.calculateSessionCost(this.data().metadata, adjustedMinutes);
    this.finalAmount.set(costInfo.total);
  }

  confirmCheckout() {
    const payload = {
      transactionId: this.data().id,
      endTime: this.currentTime + ':00',
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