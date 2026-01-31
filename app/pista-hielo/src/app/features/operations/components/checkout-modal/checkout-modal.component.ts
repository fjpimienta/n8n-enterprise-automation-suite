import { Component, EventEmitter, Output, OnInit, input, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { IceOperationsService } from '@features/operations/services/ice-operation.service';
import { LucideAngularModule } from 'lucide-angular';
import { PhTransaction } from '@core/models/transaction.types';

@Component({
  selector: 'app-checkout-modal',
  standalone: true,
  imports: [CommonModule, FormsModule, LucideAngularModule],
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

  // Input requerido (Signal)
  data = input.required<PhTransaction>({ alias: 'transaction' });

  @Output() onClose = new EventEmitter<void>();
  @Output() onConfirm = new EventEmitter<any>();

  // Estados Reactivos
  zamboniApplied = signal(false);
  paymentMethod = signal<'CASH' | 'CARD' | 'TRANSFER'>('CASH');

  // --- VARIABLES CON NOMBRES QUE TU HTML ESPERA ---
  public currentTime: string = '';      // Antes: endTime
  public minutesElapsed: number = 0;    // Antes: rawElapsedMinutes

  // Signals calculados (Precios)
  public finalMinutes = signal(0);
  public finalAmount = signal(0);

  ngOnInit() {
    this.initializeModal();
  }

  initializeModal() {
    const tx = this.data();

    // 1. Hora de Salida (currentTime en tu HTML)
    const now = new Date();
    this.currentTime = now.toTimeString().split(' ')[0].substring(0, 5); // HH:mm

    // 2. Calcular tiempo real
    const startTimeStr = tx.start_time || '00:00';
    const [startH, startM] = startTimeStr.split(':').map(Number);

    const startDate = new Date();
    startDate.setHours(startH, startM, 0);

    const diffMs = now.getTime() - startDate.getTime();
    this.minutesElapsed = Math.max(0, Math.floor(diffMs / 60000)); // minutesElapsed en tu HTML

    // 3. Calcular montos iniciales
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
    // Si hay Zamboni, descontamos 15 min
    const adjustedMinutes = this.zamboniApplied()
      ? Math.max(0, this.minutesElapsed - 15)
      : this.minutesElapsed;

    this.finalMinutes.set(adjustedMinutes);

    // Usamos el servicio para calcular precio exacto
    const costInfo = this.iceService.calculateSessionCost(this.data().metadata, adjustedMinutes);
    this.finalAmount.set(costInfo.total);
  }

  // --- FUNCIÓN CON NOMBRE QUE TU HTML ESPERA ---
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