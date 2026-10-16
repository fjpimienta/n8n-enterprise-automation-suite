import type { PendingAuthorization } from '@core/models/pending-authorization.model';

/** Label used for VENTA requests of an order that carry no transit guide. */
export const NO_GUIDE_LABEL = 'Sin guía';
const NO_CATEGORY_LABEL = 'Sin categoría';

export interface SaleGuideGroup {
  /** Transit guide folio, or NO_GUIDE_LABEL. */
  guiaTransito: string;
  requests: PendingAuthorization[];
  /** Animals per category (current category from the embedded livestock join). */
  categoryCounts: Record<string, number>;
}

export interface SaleOrderGroup {
  orderCode: string;
  /** `sale_order_id` (migration 074); falls back to the order code when a row lacks it. */
  saleOrderId: string;
  /** Requester email(s) of the order's requests, comma separated when several. */
  requestedBy: string;
  guides: SaleGuideGroup[];
  /** Number of requests (one per animal) of the active company in this order. */
  total: number;
  /** Rows of this order that belong to another company were seen and excluded (never resolved here). */
  hasForeignRows: boolean;
}

export interface SaleOrderGrouping {
  orders: SaleOrderGroup[];
  /** Rows of the active company that are not VENTA-with-order: shown as a plain list, as before. */
  ungrouped: PendingAuthorization[];
  /** Rows of other companies seen in the input and excluded (expected 0: the gateway scopes the list). */
  foreignExcluded: number;
}

const trimmed = (value: unknown): string | null =>
  typeof value === 'string' && value.trim() ? value.trim() : null;

export function orderCodeFor(row: PendingAuthorization): string | null {
  return trimmed(row.payload?.orden_venta);
}

export function guideCodeFor(row: PendingAuthorization): string | null {
  return trimmed(row.payload?.guia_transito);
}

/** Fail-closed: a row belongs to the active company only when both ids are known and equal. */
export function isOwnCompanyRow(row: Pick<PendingAuthorization, 'id_company'>, activeCompanyId: number | null | undefined): boolean {
  const active = Number(activeCompanyId);
  return Number.isInteger(active) && active > 0 && Number(row.id_company) === active;
}

const byCode = (a: string, b: string) => a.localeCompare(b, 'es', { numeric: true });

/**
 * Groups pending requests of the ACTIVE company by sale order (`payload.orden_venta`) and, inside
 * each order, by transit guide. Only VENTA rows with an order code are grouped; everything else of
 * the active company stays in `ungrouped`. Rows of any other company are never returned: they only
 * mark their order with `hasForeignRows` (its ADMIN authorizes them separately).
 */
export function groupSaleAuthorizations(
  rows: readonly PendingAuthorization[],
  activeCompanyId: number | null | undefined
): SaleOrderGrouping {
  const orders = new Map<string, { orderCode: string; saleOrderId: string; requesters: Set<string>; guides: Map<string, PendingAuthorization[]>; hasForeignRows: boolean }>();
  const ungrouped: PendingAuthorization[] = [];
  const foreignOrderKeys = new Set<string>();
  let foreignExcluded = 0;

  const keyFor = (row: PendingAuthorization, code: string) => trimmed(row.sale_order_id) ?? code;

  for (const row of rows) {
    const code = row.tipo_evento === 'VENTA' ? orderCodeFor(row) : null;

    if (!isOwnCompanyRow(row, activeCompanyId)) {
      foreignExcluded++;
      if (code) foreignOrderKeys.add(keyFor(row, code));
      continue;
    }
    if (!code) {
      ungrouped.push(row);
      continue;
    }

    const key = keyFor(row, code);
    let order = orders.get(key);
    if (!order) {
      order = { orderCode: code, saleOrderId: key, requesters: new Set(), guides: new Map(), hasForeignRows: false };
      orders.set(key, order);
    }
    if (row.solicitado_por_email) order.requesters.add(row.solicitado_por_email);
    const guide = guideCodeFor(row) ?? NO_GUIDE_LABEL;
    const list = order.guides.get(guide) ?? [];
    list.push(row);
    order.guides.set(guide, list);
  }

  const result: SaleOrderGroup[] = [...orders.values()].map(order => {
    const guides: SaleGuideGroup[] = [...order.guides.entries()]
      .map(([guiaTransito, requests]) => ({ guiaTransito, requests, categoryCounts: countCategories(requests) }))
      .sort((a, b) => byCode(a.guiaTransito, b.guiaTransito));
    return {
      orderCode: order.orderCode,
      saleOrderId: order.saleOrderId,
      requestedBy: [...order.requesters].sort().join(', '),
      guides,
      total: guides.reduce((sum, g) => sum + g.requests.length, 0),
      hasForeignRows: foreignOrderKeys.has(order.saleOrderId)
    };
  }).sort((a, b) => byCode(a.orderCode, b.orderCode));

  return { orders: result, ungrouped, foreignExcluded };
}

export function countCategories(requests: readonly PendingAuthorization[]): Record<string, number> {
  const counts: Record<string, number> = {};
  for (const row of requests) {
    const category = trimmed(row.cattle_livestock_data?.category) ?? NO_CATEGORY_LABEL;
    counts[category] = (counts[category] ?? 0) + 1;
  }
  return counts;
}

/** "3 VACA · 1 NOVILLO", most frequent first. */
export function formatCategoryCounts(counts: Record<string, number>): string {
  return Object.entries(counts)
    .sort((a, b) => b[1] - a[1] || byCode(a[0], b[0]))
    .map(([category, count]) => `${count} ${category}`)
    .join(' · ');
}

/** Distinct, sorted order codes / guides present in a list (for the quick filters). */
export function distinctOrderCodes(rows: readonly PendingAuthorization[]): string[] {
  return [...new Set(rows.map(orderCodeFor).filter((c): c is string => !!c))].sort(byCode);
}

export function distinctGuides(rows: readonly PendingAuthorization[]): string[] {
  return [...new Set(rows.map(guideCodeFor).filter((g): g is string => !!g))].sort(byCode);
}

/** Quick filters: '' = any. Applies to both the plain list and the grouped view. */
export function matchesSaleFilters(row: PendingAuthorization, orderCode: string, guide: string): boolean {
  if (orderCode && orderCodeFor(row) !== orderCode) return false;
  if (guide && guideCodeFor(row) !== guide) return false;
  return true;
}
