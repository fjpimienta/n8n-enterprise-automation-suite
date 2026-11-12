/**
 * Code-constant switch for the panel livestock ALTA flow (preview -> confirm through
 * `registerLivestockPanel`). OFF keeps the legacy `altaForm` + `createLivestock` flow exactly as
 * it was. Turning it ON is a one-line PR (PR 5); removing the legacy flow is PR 6.
 *
 * Deliberately NOT in `src/environments/`: rollback is reverting a one-line change.
 */
export const PANEL_LIVESTOCK_ALTA_ENABLED = false;

/**
 * Per-tenant allow-list of the panel ALTA flow: only companies listed here get the new flow; everyone
 * else keeps the legacy one. Rollback / kill switch: set it to `[]` (one-line PR) and nobody gets it.
 */
export const PANEL_LIVESTOCK_ALTA_TENANTS: readonly number[] = [3];

/**
 * Fail-closed check of the ACTIVE tenant against the allow-list. Accepts a number or a numeric string
 * ("3", " 3 "); anything else (null, '', NaN, "3abc", 3.5, true…) and an empty list give `false`.
 */
export function isPanelAltaEnabledForTenant(
  tenantId: unknown,
  allowed: readonly number[] = PANEL_LIVESTOCK_ALTA_TENANTS
): boolean {
  let id: number;
  if (typeof tenantId === 'number') id = tenantId;
  else if (typeof tenantId === 'string' && /^\s*\d+\s*$/.test(tenantId)) id = Number(tenantId.trim());
  else return false;
  return Number.isInteger(id) && allowed.includes(id);
}
