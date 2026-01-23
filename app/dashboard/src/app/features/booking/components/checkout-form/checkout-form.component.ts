import { CommonModule } from '@angular/common';
import { Component, EventEmitter, inject, input, OnInit, Output } from '@angular/core';
import { FormControl, FormGroup, ReactiveFormsModule, Validators } from '@angular/forms'; // Añadir Validators
import { Room } from '@core/models/hotel.types';
import { BookingService } from '@features/booking/services/booking.service';
import { HotelService } from '@features/dashboard/services/hotel.service';

@Component({
  selector: 'app-checkout-form',
  standalone: true,
  imports: [CommonModule, ReactiveFormsModule], // Solo ReactiveFormsModule
  templateUrl: './checkout-form.component.html',
  styleUrl: './checkout-form.component.css',
})
export class CheckoutFormComponent implements OnInit {
  private bookingService = inject(BookingService);

  // Inputs recibidos del Dashboard
  room = input.required<Room | null>();
  reservation = input.required<any>(); // Hacemos requerido la reserva

  @Output() saved = new EventEmitter<void>(); // Avisa que terminó bien
  @Output() canceled = new EventEmitter<void>(); // Avisa que canceló

  // Formulario Reactivo
  checkoutForm = new FormGroup({
    tvRemote: new FormControl(false, Validators.requiredTrue), // Obligatorio true
    acRemote: new FormControl(false, Validators.requiredTrue), // Obligatorio true
    keys: new FormControl(false, Validators.requiredTrue),     // Obligatorio true
    notes: new FormControl('')
  });

  ngOnInit() { }

  /* Acción de Cancelar */
  onCancel() {
    this.canceled.emit();
  }

  /* Acción de Confirmar */
  async confirmFullCheckout() {
    // 1. Validación visual
    if (this.checkoutForm.invalid) {
      this.checkoutForm.markAllAsTouched(); // Muestra errores en rojo
      alert("⚠️ Debe validar la entrega de TV, Aire Acondicionado y Llaves.");
      return;
    }

    const room = this.room();
    const booking = this.reservation();

    if (!room || !booking) return;

    // 2. Preparar el reporte basado en el formulario
    const values = this.checkoutForm.value;
    const reporte = `TV: ${values.tvRemote ? '✅' : '❌'}, AC: ${values.acRemote ? '✅' : '❌'}. Obs: ${values.notes}`;

    // Objeto para el backend
    const checkoutChecks = {
      tvRemote: values.tvRemote,
      acRemote: values.acRemote,
      keys: values.keys,
      notes: values.notes
    };

    try {
      // 3. Llamada al servicio
      await this.bookingService.processCheckout(room, booking.id, reporte, checkoutChecks);
      // 4. Avisar al padre que todo salió bien
      this.saved.emit();
    } catch (error) {
      console.error(error);
      alert('Fallo al procesar el Check-out.');
    }
  }
}