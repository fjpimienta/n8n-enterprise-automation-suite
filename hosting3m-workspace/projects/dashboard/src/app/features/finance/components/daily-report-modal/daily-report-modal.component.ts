import { Component, inject, signal, computed, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { BookingService } from '@features/booking/services/booking.service';
import { ReportService } from '@features/finance/services/report.service';
import { PdfExportConfig, PdfExportService } from 'ui-pdf-export';

@Component({
  selector: 'app-daily-report-modal',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './daily-report-modal.component.html',
  styleUrl: './daily-report-modal.component.css',
})
export class DailyReportModalComponent implements OnInit {
  public reportService = inject(ReportService);
  public bookingService = inject(BookingService);
  private pdfService = inject(PdfExportService);

  isLoading = signal(true);

  private rawBookings = signal<any[]>([]);
  private rawExpenses = signal<any[]>([]);

  currentFilter = signal<'day' | 'week' | 'month' | 'year' | 'custom'>('day');
  customStartDate = signal<string>('');
  customEndDate = signal<string>('');
  activeTab = signal<'ingresos' | 'gastos' | 'por-habitacion'>('ingresos');

  // FILTROS AVANZADOS
  incomeBillingFilter = signal<'Todos' | 'Facturado' | 'No Facturado'>('Todos');
  incomeRoomFilter = signal<string>('Todos');
  incomeStatusFilter = signal<string>('Todos');
  incomePaymentFilter = signal<string>('Todos');

  expensePaymentFilter = signal<'Todos' | 'Efectivo' | 'Transferencia' | 'Tarjeta Corp'>('Todos');
  expenseConceptFilter = signal<string>('');
  expenseCategoryFilter = signal<string>('Todas');

  // ESTADOS DE AGRUPACIÓN
  incomeGroup = signal<'none' | 'room' | 'status' | 'billing' | 'payment'>('none');
  expenseGroup = signal<'none' | 'category' | 'payment'>('none');

  // 🧠 MEMORIA DE GRUPOS EXPANDIDOS (Acordeones)
  expandedIncomeGroups = signal<Set<string>>(new Set());
  expandedExpenseGroups = signal<Set<string>>(new Set());

  // 👇 AÑADE ESTAS DOS LÍNEAS AQUÍ 👇
  capitalTotal = signal<number>(0);
  saldoBancarioReal = computed(() => this.reportData().balance + this.capitalTotal());

  // --- INTERCEPTORES DE FILTROS ---
  onIncomeRoomFilterChange(val: string) {
    this.incomeRoomFilter.set(val);
    if (val !== 'Todos' && this.incomeGroup() === 'room') this.onIncomeGroupChange('none');
  }
  onIncomeStatusFilterChange(val: string) {
    this.incomeStatusFilter.set(val);
    if (val !== 'Todos' && this.incomeGroup() === 'status') this.onIncomeGroupChange('none');
  }
  onIncomeBillingFilterChange(val: 'Todos' | 'Facturado' | 'No Facturado' | any) {
    this.incomeBillingFilter.set(val);
    if (val !== 'Todos' && this.incomeGroup() === 'billing') this.onIncomeGroupChange('none');
  }
  onIncomePaymentFilterChange(val: string) {
    this.incomePaymentFilter.set(val);
    if (val !== 'Todos' && this.incomeGroup() === 'payment') this.onIncomeGroupChange('none');
  }
  onExpenseCategoryFilterChange(val: string) {
    this.expenseCategoryFilter.set(val);
    if (val !== 'Todas' && this.expenseGroup() === 'category') this.onExpenseGroupChange('none');
  }
  onExpensePaymentFilterChange(val: 'Todos' | 'Efectivo' | 'Transferencia' | 'Tarjeta Corp' | any) {
    this.expensePaymentFilter.set(val);
    if (val !== 'Todos' && this.expenseGroup() === 'payment') this.onExpenseGroupChange('none');
  }

  // --- INTERCEPTORES DE AGRUPACIÓN (Limpian los acordeones al cambiar) ---
  onIncomeGroupChange(val: any) {
    this.incomeGroup.set(val);
    this.expandedIncomeGroups.set(new Set()); // Inicia todo colapsado
  }

  onExpenseGroupChange(val: any) {
    this.expenseGroup.set(val);
    this.expandedExpenseGroups.set(new Set()); // Inicia todo colapsado
  }

  // --- TOGGLES PARA EL HTML ---
  toggleIncomeGroup(key: string) {
    const current = new Set(this.expandedIncomeGroups());
    if (current.has(key)) current.delete(key);
    else current.add(key);
    this.expandedIncomeGroups.set(current);
  }

  toggleExpenseGroup(key: string) {
    const current = new Set(this.expandedExpenseGroups());
    if (current.has(key)) current.delete(key);
    else current.add(key);
    this.expandedExpenseGroups.set(current);
  }

  roomNumberMap = computed(() => {
    const map = new Map<number, string>();
    this.bookingService.rooms().forEach(r => map.set(Number(r.id), r.room_number));
    return map;
  });

  roomStatusMap = computed(() => {
    const map = new Map<number, { text: string, badge: string }>();
    this.bookingService.rooms().forEach(r => {
      if (r.status === 'maintenance') {
        map.set(Number(r.id), { text: 'MANTENIMIENTO', badge: 'bg-blue-lt' });
      } else if (r.status === 'occupied') {
        map.set(Number(r.id), { text: 'OCUPADA', badge: 'bg-red-lt' });
      } else if (r.cleaning_status === 'dirty') {
        map.set(Number(r.id), { text: 'SUCIA', badge: 'bg-orange-lt' });
      } else {
        map.set(Number(r.id), { text: 'DISPONIBLE', badge: 'bg-green-lt' });
      }
    });
    return map;
  });

  expenseCategories = computed(() => {
    const cats = new Set(this.rawExpenses().map(e => e.category || 'Operativo'));
    return ['Todas', ...Array.from(cats)];
  });

  getRoomStatus(id: any) {
    return this.roomStatusMap().get(Number(id)) ?? { text: 'N/A', badge: 'bg-secondary-lt' };
  }

  getRoomNumber(id: any): string {
    return this.roomNumberMap().get(Number(id)) ?? 'N/A';
  }

  reportData = computed(() => {
    return this.reportService.calculateDailyReport(
      this.rawBookings(),
      this.rawExpenses(),
      this.currentFilter(),
      this.customStartDate(),
      this.customEndDate(),
      this.incomeBillingFilter(),
      this.expensePaymentFilter(),
      this.incomeRoomFilter(),
      this.incomeStatusFilter(),
      this.incomePaymentFilter(),
      this.expenseConceptFilter(),
      this.expenseCategoryFilter()
    );
  });

  groupedIncome = computed(() => {
    const groupType = this.incomeGroup();
    const transactions = this.reportData().transactions;
    if (groupType === 'none') return [];

    const groupsMap = new Map<string, { label: string, items: any[] }>();

    transactions.forEach(t => {
      let key = 'Otros', label = 'Otros';

      if (groupType === 'room') {
        key = String(t.room_id);
        label = `Habitación ${this.getRoomNumber(t.room_id)}`;
      } else if (groupType === 'status') {
        key = t.status === 'cancelled' ? 'Cancelado' : (t.payment_status === 'paid' ? 'Pagado' : 'Pendiente');
        label = `Estado: ${key}`;
      } else if (groupType === 'billing') {
        key = t.is_invoiced ? 'Facturado' : 'No Facturado';
        label = `Facturación: ${key}`;
      } else if (groupType === 'payment') {
        const paymentLabels: Record<string, string> = {
          cash: 'Efectivo',
          credit_card: 'Tarjeta de Crédito',
          transfer: 'Transferencia'
        };
        key = t.payment_method || 'pending';
        label = `Método: ${paymentLabels[key] ?? 'Pago Pendiente'}`;
      }

      if (!groupsMap.has(key)) groupsMap.set(key, { label, items: [] });
      groupsMap.get(key)!.items.push(t);
    });

    return Array.from(groupsMap.entries()).map(([key, group]) => ({
      key,
      label: group.label,
      items: group.items,
      total: group.items.reduce((sum, i) => sum + (i.status !== 'cancelled' ? (Number(i.total_amount) || 0) : 0), 0)
    })).sort((a, b) => a.label.localeCompare(b.label));
  });

  roomCostSummary = computed(() => {
    const expenses = this.rawExpenses().filter(e => e.room_id != null);
    const map = new Map<number, { roomNumber: string; total: number; count: number }>();

    expenses.forEach(e => {
      const roomId = Number(e.room_id);
      const roomNumber = this.getRoomNumber(roomId);
      if (!map.has(roomId)) map.set(roomId, { roomNumber, total: 0, count: 0 });
      const entry = map.get(roomId)!;
      entry.total += Number(e.amount) || 0;
      entry.count += 1;
    });

    return Array.from(map.entries())
      .map(([roomId, data]) => ({ roomId, ...data }))
      .sort((a, b) => b.total - a.total);
  });

  readonly totalRoomCosts = computed(() =>
    this.roomCostSummary().reduce((sum, r) => sum + r.total, 0)
  );

  groupedExpenses = computed(() => {
    const groupType = this.expenseGroup();
    const transactions = this.reportData().expenseTransactions;
    if (groupType === 'none') return [];

    const groupsMap = new Map<string, { label: string, items: any[] }>();

    transactions.forEach(ex => {
      let key = 'Otros', label = 'Otros';

      if (groupType === 'category') {
        key = ex.category || 'Operativo';
        label = `Categoría: ${key}`;
      } else if (groupType === 'payment') {
        key = ex.payment_method || 'N/A';
        label = `Método de Pago: ${key}`;
      }

      if (!groupsMap.has(key)) groupsMap.set(key, { label, items: [] });
      groupsMap.get(key)!.items.push(ex);
    });

    return Array.from(groupsMap.entries()).map(([key, group]) => ({
      key,
      label: group.label,
      items: group.items,
      total: group.items.reduce((sum, i) => sum + (Number(i.amount) || 0), 0)
    })).sort((a, b) => b.total - a.total);
  });

  ngOnInit() {
    if (this.bookingService.rooms().length === 0) this.bookingService.loadRooms();
    this.loadData();
    this.loadCapital(); // 👈 AÑADE ESTA LÍNEA
  }

  // 👇 AÑADE ESTE MÉTODO JUSTO DEBAJO DE ngOnInit 👇
  async loadCapital() {
    const total = await this.reportService.getCapitalTotal();
    this.capitalTotal.set(total);
  }

  async loadData() {
    this.isLoading.set(true);
    try {
      const dates = this.reportService.getPeriodDates(this.currentFilter(), this.customStartDate(), this.customEndDate());
      const [bookings, expenses] = await Promise.all([
        this.reportService.getRawBookingsForReport(dates.start, dates.end),
        this.reportService.getRawExpensesForReport(dates.start, dates.end)
      ]);
      this.rawBookings.set(bookings);
      this.rawExpenses.set(expenses);
    } catch (error) {
      console.error('Error cargando datos financieros:', error);
    } finally {
      this.isLoading.set(false);
    }
  }

  setFilter(f: 'day' | 'week' | 'month' | 'year' | 'custom') {
    this.currentFilter.set(f);
    if (f !== 'custom') {
      this.customStartDate.set('');
      this.customEndDate.set('');
      this.loadData();
    }
  }

  onCustomDateChange() {
    if (this.customStartDate() && this.customEndDate()) this.loadData();
  }

  getNights(checkIn: string, checkOut: string): number {
    if (!checkIn || !checkOut) return 1;
    const start = new Date(checkIn);
    const end = new Date(checkOut);
    const diffDays = Math.ceil(Math.abs(end.getTime() - start.getTime()) / (1000 * 60 * 60 * 24));
    return diffDays === 0 ? 1 : diffDays;
  }

  private getPeriodLabel(): string {
    const labels: Record<string, string> = { 'day': 'Día Actual', 'week': 'Semana Actual', 'month': 'Mes Actual', 'year': 'Año Actual' };
    if (this.currentFilter() === 'custom') {
      const start = this.customStartDate() ? new Date(this.customStartDate()).toLocaleDateString() : '?';
      const end = this.customEndDate() ? new Date(this.customEndDate()).toLocaleDateString() : '?';
      return `${start} AL ${end}`;
    }
    return labels[this.currentFilter()] || 'Periodo';
  }

  printReport() {
    const stats = this.reportData();
    const period = this.getPeriodLabel();
    let reportItems: any[] = [];

    if (this.incomeGroup() === 'none') {
      stats.transactions.forEach((t: any) => {
        let state = t.payment_status === 'paid' ? 'PAGADO' : 'PENDIENTE';
        if (t.status === 'cancelled') state = 'CANCELADO';
        reportItems.push({
          concept: `[INGRESO] Hab. ${this.getRoomNumber(t.room_id)}`,
          description: `Ingreso: ${new Date(t.check_in).toLocaleDateString()} | Estado: ${state}`,
          quantity: 1, unitPrice: Number(t.total_amount) || 0, total: Number(t.total_amount) || 0
        });
      });
    } else {
      this.groupedIncome().forEach(g => {
        reportItems.push({ concept: `📁 [GRUPO] ${g.label.toUpperCase()}`, description: `--- SUBTOTAL DEL GRUPO ---`, quantity: '', unitPrice: '', total: g.total });
        g.items.forEach((t: any) => {
          let state = t.payment_status === 'paid' ? 'PAGADO' : 'PENDIENTE';
          if (t.status === 'cancelled') state = 'CANCELADO';
          reportItems.push({
            concept: `   ↳ Hab. ${this.getRoomNumber(t.room_id)}`,
            description: `Ingreso: ${new Date(t.check_in).toLocaleDateString()} | Estado: ${state}`,
            quantity: 1, unitPrice: Number(t.total_amount) || 0, total: Number(t.total_amount) || 0
          });
        });
      });
    }

    if (this.expenseGroup() === 'none') {
      stats.expenseTransactions.forEach((ex: any) => {
        reportItems.push({
          concept: `[GASTO] ${ex.category || 'Operativo'}`,
          description: `${ex.description} | Método: ${ex.payment_method} | Resp: ${ex.registered_by_name}`,
          quantity: 1, unitPrice: -(Number(ex.amount) || 0), total: -(Number(ex.amount) || 0)
        });
      });
    } else {
      this.groupedExpenses().forEach(g => {
        reportItems.push({ concept: `📁 [GRUPO] ${g.label.toUpperCase()}`, description: `--- SUBTOTAL DEL GRUPO ---`, quantity: '', unitPrice: '', total: -(g.total) });
        g.items.forEach((ex: any) => {
          reportItems.push({
            concept: `   ↳ ${ex.category || 'Operativo'}`,
            description: `${ex.description} | Método: ${ex.payment_method}`,
            quantity: 1, unitPrice: -(Number(ex.amount) || 0), total: -(Number(ex.amount) || 0)
          });
        });
      });
    }

    if (reportItems.length === 0) return alert('No hay información en este periodo con los filtros actuales.');

    const pdfConfig: PdfExportConfig = {
      fileName: `Corte_Caja_${period.replace(/ /g, '_')}`,
      title: `CORTE DE CAJA UNIFICADO - ${period.toUpperCase()}`,
      companyName: 'Hotel San José',
      companyAddress: 'Av. Juarez s/n, Centro, Catazajá, Chiapas',
      clientName: 'Reporte Financiero',
      clientSubtitle: `Filtros Inc: Hab:${this.incomeRoomFilter()} / Est:${this.incomeStatusFilter()} / Método:${this.incomePaymentFilter()} | Filtros Gasto: Cat:${this.expenseCategoryFilter()} / Pago:${this.expensePaymentFilter()}`,
      items: reportItems, showTaxes: false, showTotals: false, showValidity: false,
      footerTitle: 'Resumen Global',
      footerText: [
        `Ingresos Cobrados: $${stats.paid_in.toFixed(2)}`,
        `Ingresos Pendientes: $${stats.pending.toFixed(2)}`,
        `Gastos Totales: $${stats.total_expenses.toFixed(2)}`,
        `==================================`,
        `UTILIDAD NETA: $${stats.balance.toFixed(2)}`
      ]
    };
    this.pdfService.generate(pdfConfig);
  }
}