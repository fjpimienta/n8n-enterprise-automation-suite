import { Component, Output, EventEmitter, input, inject, signal, OnInit, computed, SimpleChanges, OnChanges } from '@angular/core'; // 1. Agregamos OnInit aquí
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Room } from '@core/models/hotel.types';
import { BookingService } from '@features/booking/services/booking.service';
import { DateUtilsService } from '@shared/services/data-utils.service';

@Component({
  selector: 'app-reservation-form',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './reservation-form.component.html',
  styleUrl: './reservation-form.component.css',
})
export class ReservationFormComponent implements OnInit, OnChanges { // 2. Agregamos "implements OnInit"
  private bookingService = inject(BookingService);

  reservations = input.required<any[]>();
  reservationToEdit = input<any | null>(null);
  room = input<Room | null>(null);

  @Output() saved = new EventEmitter<any>();
  @Output() onClose = new EventEmitter<void>();

  // Estados de carga (Signals)
  isSaving = signal<boolean>(false);
  isSearching = signal<boolean>(false);

  dates = { start: '', end: '' };
  availableRooms: Room[] = [];
  guest = { name: '', doc_id: '', phone: '', email: '', notes: '' };
  dateUtils = inject(DateUtilsService);

  // 🚨 FECHA BLINDADA (Ignora UTC, toma hora local de México)
  minDate = (() => {
    const now = new Date();
    const year = now.getFullYear();
    const month = String(now.getMonth() + 1).padStart(2, '0');
    const day = String(now.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
  })();

  selectedRoomForRes: Room | null = null; // Para modo simple
  selectedRooms: Room[] = [];             // Para modo múltiple (Nuevo)
  isMultiBooking: boolean = false;        // El switch

  customTotal: number = 0;
  requiresInvoice: boolean = false;       // Nuevo control para requerir factura

  recalculateTotal() {
    if (this.reservationToEdit()) return;

    const noches = this.getNights(this.dates.start, this.dates.end);
    let baseTotal = 0;
    if (this.isMultiBooking) {
      baseTotal = this.selectedRooms.reduce((acc, room) => acc + (noches * room.price_night), 0);
    } else {
      baseTotal = noches * (this.selectedRoomForRes?.price_night || 0);
    }

    // 🛠️ CÁLCULO DINÁMICO FISCAL (16% IVA + 2% ISH)
    this.customTotal = this.requiresInvoice ? (baseTotal * 1.18) : baseTotal;
  }

  toggleRoom(room: Room) {
    if (this.isMultiBooking) {
      const index = this.selectedRooms.findIndex(r => r.id === room.id);
      if (index >= 0) this.selectedRooms.splice(index, 1);
      else this.selectedRooms.push(room);
    } else {
      this.selectedRoomForRes = room;
    }
    this.recalculateTotal();
  }

  isRoomSelected(room: Room): boolean {
    if (this.isMultiBooking) {
      return this.selectedRooms.some(r => r.id === room.id);
    } else {
      return this.selectedRoomForRes?.id === room.id;
    }
  }

  ngOnInit() {
    if (this.room()) {
      this.selectedRoomForRes = this.room();
    }
  }

  ngOnChanges(changes: SimpleChanges) {
    if (changes['reservationToEdit'] && this.reservationToEdit()) {
      const res = this.reservationToEdit();
      this.dates.start = res.check_in.split('T')[0];
      this.dates.end = res.check_out.split('T')[0];
      this.guest.name = res.hotel_guests_data?.full_name || res.guest_name || '';
      let doc_id = this.guest.doc_id;
      if (doc_id && doc_id.startsWith('INT-')) {
        doc_id = ''; // Lo dejamos vacío visualmente
      }
      let email = this.guest.email;
      if (email && email.startsWith('no-email-')) {
        email = ''; // Lo dejamos vacío visualmente
      }
      this.guest.doc_id = doc_id;
      this.guest.email = email;
      this.guest.phone = res.hotel_guests_data?.phone || res.guest_phone || '';
      this.guest.notes = res.hotel_guests_data?.notes || res.guest_notes || '';

      this.requiresInvoice = res.is_invoiced === true;
      this.customTotal = res.total_amount || 0;

      // Ejecutamos la búsqueda para mostrar la habitación actual como seleccionada
      this.searchRooms();
    }
  }

  /* Calcula la cantidad de noches entre dos fechas */
  getNights(start: string, end: string): number {
    if (!start || !end) return 0;
    const startDate = new Date(start);
    const endDate = new Date(end);
    const diffTime = endDate.getTime() - startDate.getTime();
    const diffDays = Math.ceil(diffTime / (1000 * 60 * 60 * 24));
    return diffDays > 0 ? diffDays : 0;
  }

  /* Busca habitaciones disponibles en las fechas seleccionadas */
  async searchRooms() {
    if (!this.dates.start || !this.dates.end) {
      alert('Seleccione fechas de entrada y salida');
      return;
    }

    this.isSearching.set(true); // 3. ENCENDEMOS EL LOADING

    try {
      const allRooms = this.bookingService.rooms();
      const excludeId = this.reservationToEdit()?.id;
      this.availableRooms = await this.bookingService.checkAvailability(
        this.dates.start,
        this.dates.end,
        allRooms,
        excludeId
      );

      if (this.room()) {
        const isStillAvailable = this.availableRooms.some(r => r.id === this.room()?.id);
        if (!isStillAvailable) {
          alert(`La Habitación ${this.room()?.room_number} ya está reservada en esas fechas. Mostrando otras.`);
          this.selectedRoomForRes = null;
        } else {
          this.selectedRoomForRes = this.room();
          this.recalculateTotal();
        }
      }

      if (this.availableRooms.length === 0) {
        alert('No hay habitaciones disponibles.');
      }
    } finally {
      this.isSearching.set(false); // 4. APAGAMOS EL LOADING
    }
  }

  /* Confirma y guarda la reserva */
  /* Confirma y guarda la reserva o cotización */
  async confirmReservation(intendedStatus: 'pending' | 'confirmed' = 'confirmed') {
    // Validaciones
    if (this.isMultiBooking && this.selectedRooms.length === 0) return;
    if (!this.isMultiBooking && !this.selectedRoomForRes) return;

    if (!this.guest.name) {
      alert('Ingrese el nombre del huésped');
      return;
    }

    this.isSaving.set(true);
    const noches = this.getNights(this.dates.start, this.dates.end);

    // Preparamos datos comunes del huésped
    let doc_id = this.guest.doc_id;
    if (doc_id && doc_id.startsWith('INT-')) doc_id = '';
    let email = this.guest.email;
    if (email && email.startsWith('no-email-')) email = '';

    try {
      if (this.reservationToEdit()) {
        // Extensión de Estancia / Modificación
        const updateData = {
          id: this.reservationToEdit().id,
          room_id: this.reservationToEdit().room_id,
          check_in: this.dates.start,
          check_out: this.dates.end, // Nueva fecha extendida
          total_amount: this.customTotal, // Nuevo monto manual
          amount_paid: this.reservationToEdit().amount_paid,       // 🛠️ ENVIAMOS LO QUE YA PAGÓ
          payment_status: this.reservationToEdit().payment_status, // 🛠️ ENVIAMOS SU ESTADO ACTUAL
          notes: this.guest.notes,
          is_invoiced: this.requiresInvoice
        };

        await this.bookingService.updateReservation(updateData);
        alert('✅ Estancia actualizada correctamente.');

        this.saved.emit();
        this.resetForm();
        this.onClose.emit();
      } else {
        // --- NUEVA LÓGICA DE CREACIÓN ---
        const roomsToBook = this.isMultiBooking ? this.selectedRooms : [this.selectedRoomForRes!];
        const totalPerRoom = this.customTotal / roomsToBook.length;
        let successCount = 0;

        for (const room of roomsToBook) {
          const reservationData = {
            room_id: room.id,
            full_name: this.guest.name,
            doc_id: doc_id,
            email: email,
            phone: this.guest.phone,
            notes: this.guest.notes,
            check_in: this.dates.start,
            check_out: this.dates.end,
            total_amount: totalPerRoom,
            is_invoiced: this.requiresInvoice,
            // 🧠 ESTADOS DINÁMICOS BASADOS EN EL BOTÓN CLICKEADO
            status: intendedStatus,
            payment_status: intendedStatus === 'confirmed' ? 'paid' : 'pending',
            amount_paid: intendedStatus === 'confirmed' ? totalPerRoom : 0
          };

          const result = await this.bookingService.createFutureReservation(reservationData, room.id);
          if (result) successCount++;
        }

        if (successCount > 0) {
          const label = intendedStatus === 'pending' ? 'Cotización(es) bloqueada(s)' : 'Reserva(s) confirmada(s)';
          alert(`¡Éxito! ${successCount} ${label} correctamente.`);
          this.saved.emit();
          this.resetForm();
          this.onClose.emit();
        }
      }
    } catch (e) {
      console.error(e);
      alert('Ocurrió un error al procesar las reservas.');
    } finally {
      this.isSaving.set(false);
    }
  }

  // Modifica resetForm para asegurar que apague el switch si se cancela o cierra total
  private resetForm() {
    this.dates = { start: '', end: '' };
    this.availableRooms = [];
    this.selectedRoomForRes = null;
    this.selectedRooms = [];
    this.guest = { name: '', doc_id: '', phone: '', email: '', notes: '' };
    this.isMultiBooking = false;
    this.customTotal = 0;
    this.requiresInvoice = false;
  }

  cancelEdit() {
    // 1. Limpiamos el formulario local
    this.resetForm();
    // 2. Avisamos al componente padre que deje de mandarnos la reserva para editar
    this.onClose.emit();
  }


}