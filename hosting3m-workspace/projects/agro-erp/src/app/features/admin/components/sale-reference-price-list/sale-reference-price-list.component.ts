import { ChangeDetectionStrategy, Component, computed, effect, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { TenantService } from 'core-auth';
import { SaleService } from '@core/services/sale.service';
import {
  SALE_MODES,
  SALE_MODE_LABEL,
  SaleMode,
  SaleReferencePrice,
  SaleReferencePriceInput
} from '@core/models/sale.model';
import { ConfirmActionModalComponent } from '@shared/components/confirm-action-modal/confirm-action-modal.component';
import { LIVESTOCK_CATEGORIES } from '@shared/utils/livestock-category.util';
import { formatCalendarDate } from '@shared/utils/authorization-deadline.util';
import { formatMoney, parseOptionalNumber, validateReferencePriceInput } from '@shared/utils/sale-income.util';

interface FormState {
  id: string | null;
  category: string;
  saleMode: SaleMode;
  referenceAmount: number | null;
  referencePricePerKg: number | null;
  validFrom: string;
  validTo: string;
  notes: string;
}

/** Today in America/Mexico_City as YYYY-MM-DD (default `valid_from`). */
const todayInCdmx = () =>
  new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Mexico_City', year: 'numeric', month: '2-digit', day: '2-digit' })
    .format(new Date());

/**
 * ADMIN screen for `cattle_sale_reference_prices` (migration 071) of the active tenant. These
 * prices only pre-fill the sale approval form; the recorded amount is always the one the ADMIN
 * confirms. Never physically deleted: "Desactivar" sets `is_active = false`.
 */
@Component({
  selector: 'app-sale-reference-price-list',
  standalone: true,
  imports: [CommonModule, ConfirmActionModalComponent],
  templateUrl: './sale-reference-price-list.component.html',
  changeDetection: ChangeDetectionStrategy.OnPush
})
export class SaleReferencePriceListComponent {
  private saleService = inject(SaleService);
  private tenantService = inject(TenantService);

  readonly categories = LIVESTOCK_CATEGORIES;
  readonly saleModes = SALE_MODES;
  readonly saleModeLabel = SALE_MODE_LABEL;

  public prices = signal<SaleReferencePrice[]>([]);
  public isLoading = signal<boolean>(false);
  public loadError = signal<string | null>(null);
  public showInactive = signal<boolean>(false);

  public form = signal<FormState | null>(null);
  public formError = signal<string | null>(null);
  public isSaving = signal<boolean>(false);
  public toDeactivate = signal<SaleReferencePrice | null>(null);

  private loadSeq = 0;

  constructor() {
    effect(() => {
      if (this.tenantService.activeTenantId()) {
        this.form.set(null);
        this.toDeactivate.set(null);
        this.load();
      }
    });
  }

  public visiblePrices = computed(() => {
    const showInactive = this.showInactive();
    return this.prices()
      .filter(p => showInactive || p.isActive)
      .sort((a, b) =>
        Number(b.isActive) - Number(a.isActive)
        || a.category.localeCompare(b.category, 'es')
        || a.saleMode.localeCompare(b.saleMode)
        || b.validFrom.localeCompare(a.validFrom)
      );
  });

  public formErrors = computed(() => {
    const f = this.form();
    return f ? validateReferencePriceInput(this.toInput(f)) : [];
  });

  public async load(): Promise<void> {
    const seq = ++this.loadSeq;
    this.isLoading.set(true);
    this.loadError.set(null);
    try {
      const prices = await this.saleService.getReferencePrices();
      if (seq === this.loadSeq) this.prices.set(prices);
    } catch (error: any) {
      if (seq !== this.loadSeq) return;
      console.error('[Agro-ERP] Error al cargar precios de referencia:', error);
      this.prices.set([]);
      this.loadError.set(error?.message || 'No se pudieron cargar los precios de referencia.');
    } finally {
      if (seq === this.loadSeq) this.isLoading.set(false);
    }
  }

  public openCreate(): void {
    this.formError.set(null);
    this.form.set({
      id: null, category: '', saleMode: 'POR_PIEZA', referenceAmount: null, referencePricePerKg: null,
      validFrom: todayInCdmx(), validTo: '', notes: ''
    });
  }

  public openEdit(price: SaleReferencePrice): void {
    this.formError.set(null);
    this.form.set({
      id: price.id,
      category: price.category,
      saleMode: price.saleMode,
      referenceAmount: price.referenceAmount,
      referencePricePerKg: price.referencePricePerKg,
      validFrom: price.validFrom,
      validTo: price.validTo ?? '',
      notes: price.notes ?? ''
    });
  }

  public closeForm(): void {
    if (!this.isSaving()) this.form.set(null);
  }

  public patchForm(patch: Partial<FormState>): void {
    this.form.update(f => (f ? { ...f, ...patch } : f));
  }

  public parseNumber(raw: string): number | null {
    return parseOptionalNumber(raw);
  }

  public async save(): Promise<void> {
    const f = this.form();
    if (!f || this.isSaving() || this.formErrors().length > 0) return;

    this.isSaving.set(true);
    this.formError.set(null);
    try {
      const input = this.toInput(f);
      if (f.id) await this.saleService.updateReferencePrice(f.id, input);
      else await this.saleService.createReferencePrice(input);
      this.form.set(null);
      await this.load();
    } catch (error: any) {
      // Gateway `error:true` messages are shown as-is.
      this.formError.set(error?.message || 'No se pudo guardar el precio de referencia.');
    } finally {
      this.isSaving.set(false);
    }
  }

  public askDeactivate(price: SaleReferencePrice): void {
    this.toDeactivate.set(price);
  }

  public async confirmDeactivate(): Promise<void> {
    const price = this.toDeactivate();
    if (!price) return;
    await this.setActive(price, false);
    this.toDeactivate.set(null);
  }

  public async reactivate(price: SaleReferencePrice): Promise<void> {
    await this.setActive(price, true);
  }

  private async setActive(price: SaleReferencePrice, isActive: boolean): Promise<void> {
    try {
      await this.saleService.setReferencePriceActive(price.id, isActive);
      await this.load();
    } catch (error: any) {
      alert(error?.message || 'No se pudo actualizar el precio de referencia.');
    }
  }

  public validityLabel(price: SaleReferencePrice): string {
    const from = formatCalendarDate(price.validFrom);
    return price.validTo ? `${from} – ${formatCalendarDate(price.validTo)}` : `Desde ${from}`;
  }

  public money(value: number | null): string {
    return formatMoney(value);
  }

  private toInput(f: FormState): SaleReferencePriceInput {
    return {
      category: f.category,
      saleMode: f.saleMode,
      referenceAmount: f.referenceAmount,
      referencePricePerKg: f.referencePricePerKg,
      validFrom: f.validFrom,
      validTo: f.validTo || null,
      notes: f.notes || null
    };
  }
}
