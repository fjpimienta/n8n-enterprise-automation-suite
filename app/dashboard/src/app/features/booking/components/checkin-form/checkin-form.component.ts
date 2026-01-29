import { Component, Output, EventEmitter, input, OnInit, OnChanges, SimpleChanges, inject } from '@angular/core';
import { FormGroup, FormControl, Validators, ReactiveFormsModule } from '@angular/forms';
import { CommonModule } from '@angular/common';
import { Room } from '@core/models/hotel.types';
import { AdminService } from '@features/admin/services/admin.service';

@Component({
  selector: 'app-checkin-form',
  standalone: true,
  imports: [CommonModule, ReactiveFormsModule],
  templateUrl: './checkin-form.component.html'
})
export class CheckinFormComponent implements OnInit, OnChanges {
  private adminService = inject(AdminService);

  room = input.required<Room | null>();
  reservation = input<any | null>(null);

  @Output() saved = new EventEmitter<any>();
  @Output() onClose = new EventEmitter<void>();

  // Variables para cálculos
  standardPrice: number = 0; // El precio real según tarifa
  discountAmount: number = 0; // La diferencia calculada
  daysCount: number = 1;

  checkinForm = new FormGroup({
    full_name: new FormControl('', [Validators.required]),
    phone: new FormControl(''),
    email: new FormControl('', [Validators.email]),
    doc_id: new FormControl(''),
    city: new FormControl(''),
    state: new FormControl(''),
    country: new FormControl('México'),
    check_out: new FormControl('', [Validators.required]),
    total_amount: new FormControl(0, [Validators.required, Validators.min(0)]), // El cobro final
    vip_status: new FormControl(false),
    requires_invoice: new FormControl(false),
    notes: new FormControl('') // La validación se agrega dinámicamente
  });

  ngOnInit() {
    this.initDefaultValues();

    this.checkinForm.get('check_out')?.valueChanges.subscribe(() => {
      this.calculateStandardPrice();
    });

    this.checkinForm.get('total_amount')?.valueChanges.subscribe((val) => {
      this.calculateDiscount(val || 0);
    });

    // Eliminamos la llamada directa aquí, porque quizás room() aun es null
    // this.calculateStandardPrice(); 
  }

  ngOnChanges(changes: SimpleChanges) {
    // 1. Si cambia la reserva (tu código original)
    if (changes['reservation'] && this.reservation()) {
      this.fillWithReservationData(this.reservation());
    }

    // 2. AGREGADO: Si cambia la habitación (o llega por primera vez)
    // Esto garantiza que tenemos datos para calcular el precio
    if (changes['room'] && this.room()) {
      // Pequeño timeout para asegurar que el formulario ya tenga fechas inicializadas
      setTimeout(() => {
        this.calculateStandardPrice();
      });
    }
  }
  // --- LÓGICA CORE ---

  /**
   * Calcula cuánto DEBERÍA costar la habitación (Precio Lista)
   * y resetea el cobro sugerido.
   */
  calculateStandardPrice() {
    const roomData = this.room();
    const checkOutDate = this.checkinForm.get('check_out')?.value;

    if (roomData && checkOutDate) {
      const start = new Date();
      start.setHours(0, 0, 0, 0);
      const end = new Date(checkOutDate);

      // Calcular diferencia en días
      const diffTime = end.getTime() - start.getTime();
      this.daysCount = Math.max(1, Math.ceil(diffTime / (1000 * 60 * 60 * 24)));

      // Precio Base = Días * Precio Noche
      this.standardPrice = this.daysCount * (roomData.price_night || 0);

      // Seteamos el valor sugerido en el input (el usuario lo puede cambiar)
      // emitEvent: true para que dispare el cálculo del descuento inmediatamente
      this.checkinForm.patchValue({ total_amount: this.standardPrice });
    }
  }

  /**
   * Calcula el descuento basado en lo que el usuario escribió.
   * Si cobra MENOS del estándar, hay descuento.
   */
  calculateDiscount(amountCharged: number) {
    // El descuento es la diferencia. Si es negativo (cobró de más), el descuento es 0.
    this.discountAmount = Math.max(0, this.standardPrice - amountCharged);

    // REGLA DE NEGOCIO: Si hay descuento, nota obligatoria
    const notesControl = this.checkinForm.get('notes');
    if (this.discountAmount > 0) {
      notesControl?.addValidators(Validators.required);
    } else {
      notesControl?.removeValidators(Validators.required);
    }
    notesControl?.updateValueAndValidity({ emitEvent: false });
  }

  // --- FIN LÓGICA CORE ---

  private initDefaultValues() {
    const tomorrow = new Date();
    tomorrow.setDate(tomorrow.getDate() + 1);
    const dateString = tomorrow.toISOString().split('T')[0];

    this.checkinForm.patchValue({ check_out: dateString });
    // Esto disparará calculateStandardPrice por la suscripción
  }

  private fillWithReservationData(res: any) {
    if (!res) return;
    const guest = res.hotel_guests_data || res.guest || {};

    // Lógica para limpiar datos dummy
    let docId = guest.doc_id || res.guest_doc_id || '';
    if (docId.startsWith('INT-')) docId = '';

    let email = guest.email || res.guest_email || '';
    if (email.startsWith('no-email-')) email = '';

    this.checkinForm.patchValue({
      full_name: guest.full_name || res.guest_name || '',
      phone: guest.phone || res.guest_phone || '',
      email: email,
      doc_id: docId,
      city: guest.city || '',
      state: guest.state || '',
      country: guest.country || 'México',
      check_out: res.check_out ? res.check_out.split('T')[0] : '',
      total_amount: res.total_amount || 0,
      vip_status: guest.vip_status || false,
      requires_invoice: guest.requires_invoice || false,
      notes: res.notes || ''
    });

    // Importante: recalcular el estándar para saber si esta reserva traía descuento implícito
    // Usamos setTimeout para asegurar que el DOM y valores iniciales estén listos
    setTimeout(() => {
      this.calculateStandardPrice();
      // Sobreescribimos el total con el que venía en la reserva (porque calculateStandardPrice lo resetea)
      if (res.total_amount) {
        this.checkinForm.patchValue({ total_amount: res.total_amount });
      }
    });
  }

  confirmCheckin() {
    const formVal = this.checkinForm.value;

    // A) LOGICA DE AUTO-GENERACIÓN USANDO EL SERVICIO

    // Si no puso INE/Pasaporte, pedimos uno al servicio
    if (!formVal.doc_id || formVal.doc_id.trim() === '') {
      this.checkinForm.patchValue({
        doc_id: this.adminService.generateInternalId()
      });
    }

    // Si no puso Correo, pedimos uno al servicio
    if (!formVal.email || formVal.email.trim() === '') {
      this.checkinForm.patchValue({
        email: this.adminService.generateDummyEmail()
      });
    }

    // B) VALIDAMOS Y ENVIAMOS
    if (this.checkinForm.valid) {
      const payload = {
        ...this.checkinForm.value,
        discount_amount: this.discountAmount
      };
      this.saved.emit(payload);
    } else {
      this.checkinForm.markAllAsTouched();
    }
  }

  closeCheckinModal() {
    this.onClose.emit();
  }

}