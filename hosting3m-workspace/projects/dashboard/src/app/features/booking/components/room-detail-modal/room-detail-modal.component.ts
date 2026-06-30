import { CommonModule } from '@angular/common';
import { Component, EventEmitter, inject, input, OnInit, Output, ChangeDetectorRef, signal, computed } from '@angular/core';
import { AssetFormModalComponent } from '@features/admin/components/asset-form-modal/asset-form-modal.component';
import { AssetService } from '@features/admin/services/asset.service';
import { ExpenseService } from '@features/finance/services/expense.service';
import { MaintenanceService } from '@features/dashboard/services/maintenance.service';

@Component({
  selector: 'app-room-detail-modal',
  standalone: true,
  imports: [CommonModule, AssetFormModalComponent],
  templateUrl: './room-detail-modal.component.html',
  styleUrl: './room-detail-modal.component.css',
})
export class RoomDetailModalComponent implements OnInit {
  private assetService = inject(AssetService);
  private expenseService = inject(ExpenseService);
  private maintenanceService = inject(MaintenanceService);
  private cdr = inject(ChangeDetectorRef);

  room = input.required<any>();
  activeBooking = input<any>();

  activeTab: string = 'assets';
  roomAssets: any[] = [];
  roomExpenses = signal<any[]>([]);
  roomTickets = signal<any[]>([]);
  loadingCosts = signal(false);

  readonly totalExpenses = computed(() =>
    this.roomExpenses().reduce((sum, e) => sum + (Number(e.amount) || 0), 0)
  );
  readonly totalTicketCosts = computed(() =>
    this.roomTickets().filter(t => t.cost).reduce((sum, t) => sum + (Number(t.cost) || 0), 0)
  );
  readonly totalRoomCost = computed(() => this.totalExpenses() + this.totalTicketCosts());

  // Datos para el modal hijo (Nuevo Inventario)
  currentAsset = signal<any>({});
  showAssetForm = false;

  @Output() onClose = new EventEmitter<void>();
  @Output() onCheckin = new EventEmitter<void>();
  @Output() onCheckout = new EventEmitter<void>();
  @Output() onReservations = new EventEmitter<void>();
  @Output() onPay = new EventEmitter<any>();
  @Output() onMaintenance = new EventEmitter<void>();
  @Output() onFinishMaintenance = new EventEmitter<void>();
  @Output() onMarkAsClean = new EventEmitter<void>();
  @Output() onOpenChecklist = new EventEmitter<void>();
  @Output() onCancelRes = new EventEmitter<any>();
  @Output() onQuickExtend = new EventEmitter<void>();
  @Output() onRegisterExpense = new EventEmitter<number>();

  ngOnInit() {
    this.loadAssets();
  }

  async loadAssets() {
    const currentRoom = this.room();
    if (!currentRoom || !currentRoom.id) return;

    try {
      const respuesta = await this.assetService.getAssetsByRoom(currentRoom.id);
      this.roomAssets = (respuesta || []).filter((item: any) => item && item.id);
      this.cdr.detectChanges();
    } catch (error) {
      this.roomAssets = [];
    }
  }

  async loadRoomCosts() {
    const roomId = this.room()?.id;
    if (!roomId) return;

    this.loadingCosts.set(true);
    try {
      const [expenses, tickets] = await Promise.all([
        this.expenseService.getExpensesByRoom(roomId),
        this.maintenanceService.getTickets({ room_id: roomId })
      ]);
      this.roomExpenses.set(expenses);
      this.roomTickets.set(tickets.filter((t: any) => t.cost));
    } catch (error) {
      this.roomExpenses.set([]);
      this.roomTickets.set([]);
    } finally {
      this.loadingCosts.set(false);
      this.cdr.detectChanges();
    }
  }

  switchTab(tab: string) {
    this.activeTab = tab;
    if (tab === 'costs') this.loadRoomCosts();
  }

  openAssetForm() {
    // 1. Inicializamos el activo con la habitación actual ya seleccionada
    this.currentAsset.set({
      name: '',
      status: 'GOOD',
      category: 'MOBILIARIO',
      current_room_id: this.room().id // <--- CLAVE: Pre-asignamos la habitación
    });

    // 2. Mostramos el modal
    this.showAssetForm = true;
  }

  handleAssetSaved() {
    this.showAssetForm = false;
    this.loadAssets(); // Recargar la lista para ver el nuevo activo
  }

  handlePaymentClick(booking: any) {
    const total = Number(booking.total_amount) || 0;
    const paid = Number(booking.amount_paid) || 0;
    const remaining = total - paid;

    const input = window.prompt(
      `💰 REGISTRO DE ABONO\n\n` +
      `Huésped: ${booking.hotel_guests_data?.full_name || 'N/A'}\n` +
      `Total de la Estancia: $${total.toFixed(2)}\n` +
      `Monto Pagado a la fecha: $${paid.toFixed(2)}\n` +
      `Saldo Restante: $${remaining.toFixed(2)}\n\n` +
      `Ingrese el monto que el huésped está abonando en este momento:`,
      remaining.toString()
    );

    if (input === null) return;

    const amountToPay = parseFloat(input);
    if (isNaN(amountToPay) || amountToPay <= 0) {
      alert('❌ Por favor, ingrese un monto válido mayor a $0.');
      return;
    }

    if (amountToPay > remaining) {
      const confirmOverpay = window.confirm(`El abono ($${amountToPay}) es mayor al saldo restante ($${remaining}). ¿Desea registrarlo como saldo a favor / propina?`);
      if (!confirmOverpay) return;
    }

    this.onPay.emit({ booking, amount: amountToPay });
  }

  isExpired(dateStr: string | undefined): boolean {
    if (!dateStr) return false;
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const expiry = new Date(dateStr);
    return expiry < today;
  }

  isBookingForToday(): boolean {
    const b = this.activeBooking();
    if (!b) return false;
    if (this.room().status === 'occupied') return true;

    const now = new Date();
    const year = now.getFullYear();
    const month = String(now.getMonth() + 1).padStart(2, '0');
    const day = String(now.getDate()).padStart(2, '0');
    const todayStr = `${year}-${month}-${day}`;

    const inStr = String(b.check_in).split(/[ T]/)[0];
    return inStr <= todayStr;
  }
}