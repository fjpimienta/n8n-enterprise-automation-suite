import { Component, OnInit, computed, input, output, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import {
  PAYMENT_METHODS,
  PAYMENT_METHOD_LABEL,
  PaymentMethod,
  SALE_MODES,
  SALE_MODE_LABEL,
  SaleData,
  SaleMode,
  SaleReferencePrice
} from '@core/models/sale.model';
import {
  batchTotal,
  buildSaleData,
  computePricePerKg,
  formatMoney,
  isPositiveTwoDecimals,
  parseOptionalNumber,
  pickReferencePrice,
  suggestAmount,
  validateSaleData
} from '@shared/utils/sale-income.util';
import { formatCalendarDate } from '@shared/utils/authorization-deadline.util';

/** One pending VENTA request to approve, already resolved to display values by the parent. */
export interface SaleApprovalItem {
  requestId: string;
  identifier: string;
  category: string | null;
  species: string | null;
  /** YYYY-MM-DD, the date the server will record (see `saleDateFor`). */
  saleDate: string;
  guide: string | null;
}

export interface SaleApprovalSubmit {
  entries: { requestId: string; data: SaleData }[];
  /** Batch only: when set, rows blocked by the sanitary rule are retried with APROBADO_CON_EXCEPCION. */
  exceptionNotes: string | null;
}

interface RowState {
  item: SaleApprovalItem;
  /** Manual amount; only used once `touched` is true. */
  amount: number | null;
  weightKg: number | null;
  touched: boolean;
}

interface RowView {
  item: SaleApprovalItem;
  reference: SaleReferencePrice | null;
  amount: number | null;
  weightKg: number | null;
  pricePerKg: number | null;
  fromReference: boolean;
  amountInvalid: boolean;
  weightInvalid: boolean;
  data: SaleData;
  errors: string[];
}

/**
 * Sale form shown when an ADMIN approves VENTA requests (migration 071). Prices are set only
 * here, never by the requester. While an amount has not been edited by hand it stays derived
 * from the reference price (same tenant, category, mode, active, valid on the sale date), or
 * from the batch default amount when there is no reference.
 */
@Component({
  selector: 'app-sale-approval-modal',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './sale-approval-modal.component.html'
})
export class SaleApprovalModalComponent implements OnInit {
  items = input.required<SaleApprovalItem[]>();
  referencePrices = input<SaleReferencePrice[]>([]);
  variant = input<'single' | 'batch'>('single');
  submitting = input<boolean>(false);
  /** Backend error of the last attempt, shown inline; the form keeps everything typed. */
  errorMessage = input<string | null>(null);

  confirm = output<SaleApprovalSubmit>();
  cancel = output<void>();

  readonly saleModes = SALE_MODES;
  readonly saleModeLabel = SALE_MODE_LABEL;
  readonly paymentMethods = PAYMENT_METHODS;
  readonly paymentMethodLabel = PAYMENT_METHOD_LABEL;

  public mode = signal<SaleMode>('POR_PIEZA');
  public buyer = signal<string>('');
  public paymentMethod = signal<PaymentMethod | ''>('');
  public invoiced = signal<boolean>(false);
  public invoiceFolio = signal<string>('');
  public defaultAmount = signal<number | null>(null);
  public exceptionEnabled = signal<boolean>(false);
  public exceptionNotes = signal<string>('');
  private rowStates = signal<RowState[]>([]);

  ngOnInit(): void {
    this.rowStates.set(this.items().map(item => ({ item, amount: null, weightKg: null, touched: false })));
  }

  public isBatch = computed(() => this.variant() === 'batch');
  public isPorKg = computed(() => this.mode() === 'POR_KG');

  public rows = computed<RowView[]>(() => {
    const mode = this.mode();
    const prices = this.referencePrices();
    const fallback = this.isBatch() ? this.defaultAmount() : null;
    const shared = {
      mode,
      buyer: this.buyer(),
      // '' fails validation on purpose: the payment method must be chosen explicitly.
      paymentMethod: this.paymentMethod() as PaymentMethod,
      invoiced: this.invoiced(),
      invoiceFolio: this.invoiceFolio()
    };

    return this.rowStates().map(state => {
      const reference = pickReferencePrice(prices, state.item.category, mode, state.item.saleDate);
      const suggested = suggestAmount(reference, mode, state.weightKg);
      const amount = state.touched ? state.amount : (suggested ?? fallback);
      const weightKg = mode === 'POR_KG' ? state.weightKg : null;
      const data = buildSaleData({ ...shared, amount, weightKg });
      const errors = validateSaleData(data);
      return {
        item: state.item,
        reference,
        amount,
        weightKg,
        pricePerKg: mode === 'POR_KG' ? computePricePerKg(amount, weightKg) : null,
        fromReference: !state.touched && suggested !== null,
        amountInvalid: !isPositiveTwoDecimals(amount),
        weightInvalid: mode === 'POR_KG' && !isPositiveTwoDecimals(weightKg),
        data,
        errors
      };
    });
  });

  public total = computed(() => batchTotal(this.rows()));

  /** Unique validation messages across all rows (shared fields repeat per row otherwise). */
  public errors = computed(() => {
    const messages = new Set<string>();
    for (const row of this.rows()) row.errors.forEach(e => messages.add(e));
    if (this.isBatch() && this.exceptionEnabled() && !this.exceptionNotes().trim()) {
      messages.add('Escribe la justificación de la excepción sanitaria.');
    }
    return [...messages];
  });

  public canSubmit = computed(() => !this.submitting() && this.rows().length > 0 && this.errors().length === 0);

  public setMode(value: string): void {
    this.mode.set(value as SaleMode);
  }

  public setAmount(index: number, raw: string): void {
    const amount = parseOptionalNumber(raw);
    this.rowStates.update(rows => rows.map((r, i) => (i === index ? { ...r, amount, touched: true } : r)));
  }

  public setWeight(index: number, raw: string): void {
    const weightKg = parseOptionalNumber(raw);
    this.rowStates.update(rows => rows.map((r, i) => (i === index ? { ...r, weightKg } : r)));
  }

  /** Batch: overwrites every row with the default amount (they become manual amounts). */
  public applyDefaultToAll(): void {
    const amount = this.defaultAmount();
    if (amount === null) return;
    this.rowStates.update(rows => rows.map(r => ({ ...r, amount, touched: true })));
  }

  /** Back to the reference/default amount for every row. */
  public resetAmounts(): void {
    this.rowStates.update(rows => rows.map(r => ({ ...r, amount: null, touched: false })));
  }

  public parseNumber(raw: string): number | null {
    return parseOptionalNumber(raw);
  }

  public categorySpecies(item: SaleApprovalItem): string {
    return [item.category, item.species].filter(Boolean).join(' / ') || '—';
  }

  public money(value: number | null | undefined): string {
    return formatMoney(value);
  }

  public date(value: string): string {
    return formatCalendarDate(value);
  }

  public onConfirm(): void {
    if (!this.canSubmit()) return;
    this.confirm.emit({
      entries: this.rows().map(r => ({ requestId: r.item.requestId, data: r.data })),
      exceptionNotes: this.isBatch() && this.exceptionEnabled() ? this.exceptionNotes().trim() : null
    });
  }

  public onCancel(): void {
    if (this.submitting()) return;
    this.cancel.emit();
  }
}
