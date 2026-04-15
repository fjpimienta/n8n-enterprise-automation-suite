import { Component, inject, signal, computed, OnInit, OnDestroy, effect, EventEmitter, Output } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ReservationFormComponent } from '../reservation-form/reservation-form.component';
import { AdminService } from '@features/admin/services/admin.service';
import { HotelService } from '@features/dashboard/services/hotel.service';
import { BookingService } from '@features/booking/services/booking.service';
import { PdfExportService } from 'ui-pdf-export';

@Component({
  selector: 'app-reservation-manager',
  standalone: true,
  imports: [CommonModule, ReservationFormComponent],
  templateUrl: './reservation-manager.component.html'
})
export class ReservationManagerComponent implements OnInit, OnDestroy {
  public adminService = inject(AdminService);
  public hotelService = inject(HotelService);
  private bookingService = inject(BookingService);
  private pdfService = inject(PdfExportService);

  @Output() onSaved = new EventEmitter<void>();
  @Output() onClose = new EventEmitter<void>();

  selectedIds = signal<Set<number>>(new Set());
  selectedReservation = signal<any | null>(null);

  // Estados de interfaz
  isLoading = signal(true);
  private initCacheCleared = false;
  private fallbackTimeout: any;

  currentPage = signal(1);
  itemsPerPage = 8;

  filteredReservations = computed(() => {
    const all = this.adminService.reservations();
    const selectedRoom = this.hotelService.selectedRoom();

    // 🚨 FECHA BLINDADA (Hora local) para limpieza automática
    const now = new Date();
    const year = now.getFullYear();
    const month = String(now.getMonth() + 1).padStart(2, '0');
    const day = String(now.getDate()).padStart(2, '0');
    const todayStr = `${year}-${month}-${day}`;

    const currentRes = all.filter((r: any) => {
      // 1. Filtrar por habitación si hay una seleccionada
      if (selectedRoom && r.room_id !== selectedRoom.id) return false;

      // 2. 🛠️ REGLA DE NEGOCIO: Mostrar pending, confirmed, y AHORA TAMBIÉN checked_in
      if (r.status !== 'confirmed' && r.status !== 'pending' && r.status !== 'checked_in') {
        return false;
      }

      // 3. 🧹 LIMPIEZA DE PIPELINE Y PREVENCIÓN DE LIMBO
      if (r.check_out) {
        const checkOutStr = String(r.check_out).split(/[ T]/)[0];

        if (r.status === 'checked_in') {
          // 🚨 RESCATE DEL LIMBO: Si el huésped está físicamente adentro, NUNCA lo ocultamos.
          // Esto nos permite ver los "Overstays" (Salidas demoradas) y poder ampliar su fecha.
          return true;
        } else {
          // Es pending o confirmed. Si la fecha de salida ya pasó y nunca llegó, es un fantasma real.
          if (checkOutStr < todayStr) return false;
        }
      }

      return true;
    });

    // 4. Ordenar cronológicamente (las más próximas primero)
    const sorted = currentRes.sort((a: any, b: any) => {
      return new Date(a.check_in).getTime() - new Date(b.check_in).getTime();
    });

    return sorted;
  });

  // Verifica si un huésped se pasó de su fecha de salida
  isOverstay(res: any): boolean {
    if (res.status !== 'checked_in' || !res.check_out) return false;
    const now = new Date();
    const todayStr = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`;
    const outStr = String(res.check_out).split(/[ T]/)[0];
    return outStr < todayStr;
  }

  paginatedReservations = computed(() => {
    const startIndex = (this.currentPage() - 1) * this.itemsPerPage;
    return this.filteredReservations().slice(startIndex, startIndex + this.itemsPerPage);
  });

  totalPages = computed(() => Math.ceil(this.filteredReservations().length / this.itemsPerPage));

  constructor() {
    // 🧠 DETECCIÓN INTELIGENTE DE CARGA
    effect(() => {
      const resLength = this.adminService.reservations().length;

      // 1. Detectamos el momento en que loadReservations() limpia el arreglo para refrescar
      if (resLength === 0) {
        this.initCacheCleared = true;
      }

      // 2. Si ya se limpió y acaba de llegar la nueva data de n8n, apagamos el spinner de inmediato.
      if (this.initCacheCleared && resLength > 0) {
        this.isLoading.set(false);
        if (this.fallbackTimeout) clearTimeout(this.fallbackTimeout);
      }
    }, { allowSignalWrites: true });
  }

  ngOnInit() {
    this.isLoading.set(true);
    this.initCacheCleared = false;

    this.adminService.loadReservations();
    if (this.bookingService.rooms().length === 0) {
      this.bookingService.loadRooms();
    }

    // 3. Fallback de Seguridad: Si la base de datos realmente está en 0 y nunca llega info
    this.fallbackTimeout = setTimeout(() => {
      if (this.adminService.reservations().length === 0) {
        this.isLoading.set(false);
      }
    }, 45000); // 🚀 FIX: 45 segundos para cubrir todo el ciclo de los 5 reintentos
  }

  ngOnDestroy() {
    this.clearFilters();
    if (this.fallbackTimeout) clearTimeout(this.fallbackTimeout);
  }

  getRoomNumber(id: number): string {
    const found = this.bookingService.rooms().find((r: any) => r.id === id);
    return found ? found.room_number : 'N/A';
  }

  nextPage() {
    if (this.currentPage() < this.totalPages()) this.currentPage.update(p => p + 1);
  }

  prevPage() {
    if (this.currentPage() > 1) this.currentPage.update(p => p - 1);
  }

  editReservation(res: any) {
    const room = this.bookingService.rooms().find(r => r.id === res.room_id);
    if (room) {
      this.hotelService.selectRoom(room);
    }
    this.selectedReservation.set(res);
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  onReservationSaved() {
    this.selectedReservation.set(null);
    this.hotelService.selectRoom(null as any);
    this.adminService.loadReservations();
    this.bookingService.loadRooms();
    this.onSaved.emit();
  }

  focusNewReservation() {
    this.selectedReservation.set(null);
    this.hotelService.selectRoom(null as any);
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  toggleSelection(id: number, event: any) {
    const current = new Set(this.selectedIds());
    if (event.target.checked) current.add(id);
    else current.delete(id);
    this.selectedIds.set(current);
  }

  toggleAll(event: any) {
    const current = new Set(this.selectedIds());
    const visibleItems = this.paginatedReservations();

    if (event.target.checked) {
      visibleItems.forEach(r => current.add(r.id));
    } else {
      visibleItems.forEach(r => current.delete(r.id));
    }
    this.selectedIds.set(current);
  }

  isAllSelected(): boolean {
    const visibleItems = this.paginatedReservations();
    if (visibleItems.length === 0) return false;
    return visibleItems.every(r => this.selectedIds().has(r.id));
  }

  printSelected() {
    const ids = this.selectedIds();
    if (ids.size === 0) {
      alert('Seleccione al menos una reserva para imprimir.');
      return;
    }

    const rawReservations = this.adminService.reservations().filter((r: any) =>
      ids.has(r.id) && r.status !== 'cancelled' && r.status !== 'checked_out'
    );

    if (rawReservations.length === 0) {
      alert('Las reservas seleccionadas ya no están activas o fueron canceladas.');
      this.selectedIds.set(new Set()); // Limpiamos el estado colgante
      return;
    }
    const reportItems = this.mapToPdfItems(rawReservations);
    const clientName = rawReservations[0]?.hotel_guests_data?.full_name || rawReservations[0]?.guest_name || 'Cliente Mostrador';

    // 💡 LÓGICA DE ESTADO (Soft-Booking vs Hard-Booking)
    // Si alguna de las reservas seleccionadas está 'pending', es una Cotización.
    const isPending = rawReservations.some((r: any) => r.status === 'pending');
    const requiresInvoice = rawReservations.some((r: any) => r.is_invoiced === true);

    const foliosStr = Array.from(ids).join(', ');

    // Construimos el Título Dinámico
    let documentTitle = isPending ? 'PRESUPUESTO DE HOSPEDAJE' : 'COMPROBANTE DE RESERVA';
    if (requiresInvoice) {
      documentTitle += ' (INCLUYE IMPUESTOS)';
    }

    // Construimos el prefijo del archivo
    const filePrefix = isPending ? 'Cotizacion' : 'Reserva';

    const pdfConfig: any = {
      fileName: `${filePrefix}_${clientName.replace(/\s+/g, '_')}_Folio_${foliosStr}`,
      title: documentTitle,
      companyName: 'Hotel San José',
      companyAddress: 'Av. Juarez s/n, Centro, Catazajá, Chiapas',
      clientName: clientName,
      clientSubtitle: `Folio(s) de Reserva: ${foliosStr}`,
      items: reportItems,

      // Control Fiscal de la librería ui-pdf-export
      taxRate: requiresInvoice ? 0.16 : 0,
      ishRate: requiresInvoice ? 0.02 : 0,
      showTaxes: requiresInvoice,

      footerTitle: 'Forma de Pago',
      footerText: [
        'Transferencia a nombre de: Diana Perez Pimienta | RFC: PEPD690214I76',
        'Banco BBVA | CLABE: 012180015615151108 | No. Cuenta: 1561515110',
      ]
    };

    this.pdfService.generate(pdfConfig);
  }

  async bulkPayment() {
    const ids = this.selectedIds();
    if (ids.size === 0) return;

    // 🛠️ FIX 1: Filtrar registros fantasmas (cancelados o expirados) ANTES de procesar pagos
    const selectedRes = this.adminService.reservations().filter((r: any) =>
      ids.has(r.id) && r.status !== 'cancelled' && r.status !== 'checked_out'
    );

    // 🛠️ FIX 2: Si por alguna razón la selección solo tenía basura, abortamos y limpiamos
    if (selectedRes.length === 0) {
      alert('Las reservas seleccionadas ya no están activas o fueron canceladas.');
      this.selectedIds.set(new Set());
      return;
    }

    const clientName = selectedRes[0]?.hotel_guests_data?.full_name || selectedRes[0]?.guest_name || 'Grupo';

    // 1. Calcular deuda total del grupo seleccionado (solo los activos)
    let totalDeuda = 0;
    let totalPagado = 0;
    selectedRes.forEach(r => {
      totalDeuda += (Number(r.total_amount) || 0);
      totalPagado += (Number(r.amount_paid) || 0);
    });

    const saldoRestante = totalDeuda - totalPagado;

    if (saldoRestante <= 0) {
      alert('Las habitaciones seleccionadas ya están liquidadas.');
      this.selectedIds.set(new Set()); // Auto-limpieza por buena práctica
      return;
    }

    // 2. Solicitar monto a abonar al grupo
    const input = window.prompt(
      `💰 ABONO GRUPAL / CONFIRMACIÓN MULTIPLE\n\n` +
      `Huésped/Grupo: ${clientName}\n` +
      `Habitaciones seleccionadas: ${selectedRes.length}\n` +
      `Total de la Estancia: $${totalDeuda.toFixed(2)}\n` +
      `Saldo Restante: $${saldoRestante.toFixed(2)}\n\n` +
      `Ingrese el monto total que abonará el grupo en este momento:`,
      saldoRestante.toString()
    );

    if (input === null) return;

    const amountToPay = parseFloat(input);
    if (isNaN(amountToPay) || amountToPay <= 0) {
      alert('❌ Monto inválido. Debe ser mayor a $0.');
      return;
    }

    if (amountToPay > saldoRestante) {
      const confirmOverpay = window.confirm(`El abono ($${amountToPay}) supera el saldo ($${saldoRestante}). ¿Desea registrarlo de todos modos?`);
      if (!confirmOverpay) return;
    }

    this.isLoading.set(true);
    let remainingAbono = amountToPay;

    try {
      // 3. 🧠 Distribución Financiera en Cascada (Waterfall) - Solo procesa reservas válidas
      for (const res of selectedRes) {
        const currentTotal = Number(res.total_amount) || 0;
        const currentPaid = Number(res.amount_paid) || 0;
        const debt = currentTotal - currentPaid;

        let paymentForThisRoom = 0;
        if (remainingAbono > 0 && debt > 0) {
          paymentForThisRoom = Math.min(remainingAbono, debt);
          remainingAbono -= paymentForThisRoom;
        }

        // 4. Procesar pago en el servicio (forceConfirm = true para activar todo el grupo)
        await this.bookingService.registerPayment(res, paymentForThisRoom, true);
      }

      alert('✅ Pago distribuido y habitaciones confirmadas exitosamente.');
      this.selectedIds.set(new Set()); // Limpiamos selección post-éxito
      this.adminService.loadReservations();
      this.hotelService.clearSelection();

    } catch (e) {
      console.error(e);
      alert('❌ Ocurrió un error al procesar el pago grupal.');
    } finally {
      this.isLoading.set(false);
    }
  }

  private mapToPdfItems(reservations: any[]): any[] {
    const groups: any = {};

    reservations.forEach(res => {
      const room = this.bookingService.rooms().find((r: any) => r.id === res.room_id);
      const type = room?.type ? room.type.toLowerCase() : 'estándar';
      const formattedType = type.charAt(0).toUpperCase() + type.slice(1);
      const roomNumber = room?.room_number || 'S/N';

      const inDateStr = String(res.check_in).split(/[ T+]/)[0];
      const outDateStr = String(res.check_out).split(/[ T+]/)[0];
      const checkInDate = new Date(`${inDateStr}T12:00:00`);
      const checkOutDate = new Date(`${outDateStr}T12:00:00`);

      const dateOptions: Intl.DateTimeFormatOptions = { day: '2-digit', month: 'short', year: 'numeric' };
      const strIn = checkInDate.toLocaleDateString('es-MX', dateOptions);
      const strOut = checkOutDate.toLocaleDateString('es-MX', dateOptions);
      const dateRangeStr = `Del ${strIn} al ${strOut}`;

      const s = checkInDate.getTime();
      const e = checkOutDate.getTime();

      let nights = Math.round((e - s) / (1000 * 3600 * 24));
      if (nights < 1) nights = 1;

      // 🧠 EXTRACCIÓN INVERSA PARA LA LIBRERÍA DE PDF
      const finalTotalStored = Number(res.total_amount) || 0;
      const requiresInvoice = res.is_invoiced === true;

      // Si la reserva exige factura, la BD ya tiene el total inflado (+18%). 
      // Debemos darle a la librería el subtotal base para que su "auto-calculadora" cuadre.
      const baseTotalPerRoom = requiresInvoice ? (finalTotalStored / 1.18) : finalTotalStored;
      const baseDailyRate = baseTotalPerRoom / nights;

      // Llave estricta
      const key = `${type}-${baseDailyRate.toFixed(4)}-${nights}-${s}-${e}-${requiresInvoice}`;

      if (!groups[key]) {
        groups[key] = {
          concept: `Habitación ${formattedType}`,
          roomNumbers: [roomNumber],
          dateRange: dateRangeStr,
          description: `Hab: ${roomNumber}\n${dateRangeStr}`,
          dailyRate: baseDailyRate, // Enviamos NETO puro
          nights: nights,
          quantity: 1,
          unitPrice: baseTotalPerRoom, // Enviamos NETO puro
          total: baseTotalPerRoom      // Enviamos NETO puro
        };
      } else {
        groups[key].quantity += 1;
        groups[key].total += baseTotalPerRoom;
        groups[key].roomNumbers.push(roomNumber);
        groups[key].description = `Hab: ${groups[key].roomNumbers.join(', ')}\n${groups[key].dateRange}`;
      }
    });

    return Object.values(groups);
  }

  clearFilters() {
    this.selectedReservation.set(null);
    this.hotelService.selectRoom(null as any);
  }

  async cancelReservation(reservation: any) {
    const confirm = window.confirm(`¿Cancelar la reserva de ${reservation.hotel_guests_data?.full_name || 'este huésped'}?`);
    if (!confirm) return;

    try {
      await this.bookingService.cancelReservation(reservation.id);
      alert('✅ Reserva cancelada.');

      // 🛠️ FIX: Eliminar del Set de selección para evitar impresión fantasma
      this.selectedIds.update(set => {
        set.delete(reservation.id);
        return new Set(set);
      });

      this.adminService.loadReservations();
    } catch (error) {
      alert('❌ Error al cancelar.');
    }
  }

  async confirmReservation(reservation: any) {
    const guestName = reservation.hotel_guests_data?.full_name || reservation.guest_name || 'este huésped';

    const confirm = window.confirm(
      `🔔 ATENCIÓN: Aprobación de Reserva Web\n\n` +
      `Huésped: ${guestName}\n` +
      `Estancia: ${new Date(reservation.check_in).toLocaleDateString()} al ${new Date(reservation.check_out).toLocaleDateString()}\n\n` +
      `⚠️ IMPORTANTE: ¿Ya validaste la recepción del anticipo o pago total?\n\n` +
      `Al presionar 'Aceptar', la habitación quedará OFICIALMENTE CONFIRMADA y bloqueada en el inventario. No confirmes si el pago sigue pendiente.`
    );

    if (!confirm) return;

    try {
      await this.bookingService.confirmPendingReservation(reservation.id);
      alert('✅ Reserva web confirmada exitosamente en el calendario.');
      this.adminService.loadReservations();
      this.bookingService.loadRooms();
    } catch (error) {
      alert('❌ Error al confirmar la reserva.');
    }
  }
}