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
  selectedRoomForRes: Room | null = null;
  guest = { name: '', phone: '', email: '' };
  dateUtils = inject(DateUtilsService);
  minDate = this.dateUtils.todayStr;

  // En el componente
  totalReserva = computed(() => {
    const noches = this.getNights(this.dates.start, this.dates.end);
    return noches * (this.selectedRoomForRes?.price_night || 0);
  });

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
      this.guest.phone = res.hotel_guests_data?.phone || res.guest_phone || '';
      this.guest.email = res.hotel_guests_data?.email || res.guest_email || '';

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
  async confirmReservation() {
    if (!this.selectedRoomForRes) return;
    if (!this.guest.name) {
      alert('Ingrese el nombre del huésped');
      return;
    }

    this.isSaving.set(true); // 5. ENCENDEMOS EL LOADING DE GUARDADO

    // Calculamos el total real
    const noches = this.getNights(this.dates.start, this.dates.end);
    const total = noches * (this.selectedRoomForRes?.price_night || 0);
    const isUpdate = !!this.reservationToEdit()?.id;

    const reservationData = {
      id: isUpdate ? this.reservationToEdit().id : undefined,
      full_name: this.guest.name,
      email: this.guest.email,
      phone: this.guest.phone,
      check_in: this.dates.start,
      check_out: this.dates.end,
      total_amount: total // 6. AHORA SÍ TIENE EL MONTO REAL
    };

    try {
      if (isUpdate) {
        await this.bookingService.updateReservation(reservationData);
        alert('¡Reserva Actualizada!');
      } else {
        await this.bookingService.createFutureReservation(reservationData, this.selectedRoomForRes.id);
        alert('¡Reserva Guardada con Éxito!');
      }
      this.saved.emit();
      this.onClose.emit();
    } catch (error) {
      console.error(error);
      alert('Error al guardar la reserva');
    } finally {
      this.isSaving.set(false); // 7. APAGAMOS EL LOADING
    }
  }
}