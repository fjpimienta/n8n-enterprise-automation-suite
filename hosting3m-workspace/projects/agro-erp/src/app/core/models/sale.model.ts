/** Sale modes accepted by `fn_normalize_sale_data` (migration 071). */
export type SaleMode = 'POR_PIEZA' | 'POR_KG' | 'POR_GENETICA';
export type PaymentMethod = 'EFECTIVO' | 'TRANSFERENCIA';

export const SALE_MODES: readonly SaleMode[] = ['POR_PIEZA', 'POR_KG', 'POR_GENETICA'];
export const PAYMENT_METHODS: readonly PaymentMethod[] = ['EFECTIVO', 'TRANSFERENCIA'];

export const SALE_MODE_LABEL: Record<SaleMode, string> = {
  POR_PIEZA: 'Por pieza (al bulto)',
  POR_KG: 'Por kilo',
  POR_GENETICA: 'Por genética'
};

export const PAYMENT_METHOD_LABEL: Record<PaymentMethod, string> = {
  EFECTIVO: 'Efectivo',
  TRANSFERENCIA: 'Transferencia'
};

/**
 * `datos_venta` sent to `sp_resolver_autorizacion` when approving a VENTA. `precio_venta` is the
 * amount for THIS animal; $/kg and "bancarizado" are derived server-side.
 */
export interface SaleData {
  modo_venta: SaleMode;
  precio_venta: number;
  peso_kg?: number;
  comprador: string;
  forma_pago: PaymentMethod;
  facturado: boolean;
  folio_factura?: string;
}

/** Normalized sale stored by the SP in `pending_authorizations.payload.venta`. */
export interface StoredSaleData {
  modo_venta?: SaleMode;
  precio_venta?: number | string;
  peso_kg?: number | string | null;
  precio_kg?: number | string | null;
  comprador?: string;
  forma_pago?: PaymentMethod;
  facturado?: boolean;
  folio_factura?: string | null;
  bancarizado?: boolean;
}

/** `cattle_sale_reference_prices`, numerics already parsed (the gateway sends them as strings). */
export interface SaleReferencePrice {
  id: string;
  tenantId: number;
  category: string;
  saleMode: SaleMode;
  referenceAmount: number | null;
  referencePricePerKg: number | null;
  validFrom: string;
  validTo: string | null;
  isActive: boolean;
  notes: string | null;
  createdAt: string | null;
}

export interface SaleReferencePriceInput {
  category: string;
  saleMode: SaleMode;
  referenceAmount: number | null;
  referencePricePerKg: number | null;
  validFrom: string;
  validTo: string | null;
  notes: string | null;
}

/** `cattle_sale_income`, numerics already parsed. */
export interface SaleIncome {
  id: string;
  tenantId: number;
  livestockId: string;
  pendingAuthorizationId: string | null;
  saleDate: string;
  saleMode: SaleMode;
  amount: number;
  weightKg: number | null;
  pricePerKg: number | null;
  buyerName: string;
  paymentMethod: PaymentMethod;
  invoiced: boolean;
  invoiceFolio: string | null;
  banked: boolean;
  guiaTransito: string | null;
}
