import { Component, Output, EventEmitter, input, OnInit } from '@angular/core';
import { FormGroup, FormControl, Validators, ReactiveFormsModule } from '@angular/forms';
import { CommonModule } from '@angular/common';
import { Room } from '../../models/hotel.types';

@Component({
  selector: 'app-checkin-form',
  standalone: true,
  imports: [CommonModule, ReactiveFormsModule],
  templateUrl: './checkin-form.component.html'
})
export class CheckinFormComponent implements OnInit {
  room = input.required<Room | null>();

  @Output() saved = new EventEmitter<any>();
  @Output() canceled = new EventEmitter<void>();

  checkinForm = new FormGroup({
    full_name: new FormControl('', [Validators.required]),
    phone: new FormControl(''),
    email: new FormControl('', [Validators.email]),
    doc_id: new FormControl('', [Validators.required]),
    city: new FormControl(''),
    state: new FormControl(''),
    country: new FormControl('México'),
    check_out: new FormControl('', [Validators.required]),
    total_amount: new FormControl(0, [Validators.min(0)]),
    vip_status: new FormControl(false),
    requires_invoice: new FormControl(false), // Nuevo campo
    notes: new FormControl('') // Ahora sí coincidirá con la DB
  });

  ngOnInit() {
    this.initDefaultValues();

    // Escuchar cambios en la fecha de salida para recalcular el monto
    this.checkinForm.get('check_out')?.valueChanges.subscribe(() => {
      this.calculateTotal();
    });
  }

  private initDefaultValues() {
    // 1. Establecer fecha de mañana por defecto
    const tomorrow = new Date();
    tomorrow.setDate(tomorrow.getDate() + 1);
    const dateString = tomorrow.toISOString().split('T')[0];

    this.checkinForm.patchValue({
      check_out: dateString
    });

    // 2. Calcular monto inicial
    this.calculateTotal();
  }

  calculateTotal() {
    const roomData = this.room();
    const checkOutDate = this.checkinForm.get('check_out')?.value;

    if (roomData && checkOutDate) {
      const start = new Date();
      start.setHours(0, 0, 0, 0);
      const end = new Date(checkOutDate);

      // Calcular diferencia en días (mínimo 1 día)
      const diffTime = end.getTime() - start.getTime();
      const diffDays = Math.max(1, Math.ceil(diffTime / (1000 * 60 * 60 * 24)));

      const total = diffDays * (roomData.price_night || 0);
      this.checkinForm.patchValue({ total_amount: total }, { emitEvent: false });
    }
  }

  confirmCheckin() {
    if (this.checkinForm.valid) {
      this.saved.emit(this.checkinForm.value);
    }
  }

  closeCheckinModal() {
    this.canceled.emit();
  }
}