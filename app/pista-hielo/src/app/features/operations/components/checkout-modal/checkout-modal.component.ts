import { Component, EventEmitter, Output, OnInit, input, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { IceOperationsService } from '@features/operations/services/ice-operation.service';
import { PhTransaction } from '@core/models/transaction.types';

// 1. SOLO EL MÓDULO
import { LucideAngularModule } from 'lucide-angular';

@Component({
  selector: 'app-checkout-modal',
  standalone: true,
  // 2. IMPORTS SIMPLE
  imports: [
    CommonModule, 
    FormsModule, 
    LucideAngularModule 
  ],
  // 3. SIN PROVIDERS
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

  zamboniApplied = signal(false);
  paymentMethod = signal<'CASH' | 'CARD' | 'TRANSFER'>('CASH');

  public currentTime: string = '';
  public minutesElapsed: number = 0;
  public finalMinutes = signal(0);
  public finalAmount = signal(0);

  ngOnInit() {
    this.initializeModal();
  }

  initializeModal() {
    const tx = this.data();
    const now = new Date();
    this.currentTime = now.toTimeString().split(' ')[0].substring(0, 5);

    const startTimeStr = tx.start_time || '00:00';
    const [startH, startM] = startTimeStr.split(':').map(Number);
    const startDate = new Date();
    startDate.setHours(startH, startM, 0);

    const diffMs = now.getTime() - startDate.getTime();
    this.minutesElapsed = Math.max(0, Math.floor(diffMs / 60000));
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
    const adjustedMinutes = this.zamboniApplied()
      ? Math.max(0, this.minutesElapsed - 15)
      : this.minutesElapsed;

    this.finalMinutes.set(adjustedMinutes);
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