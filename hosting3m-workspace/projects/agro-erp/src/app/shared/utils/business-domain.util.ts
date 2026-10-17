/**
 * Single source of truth for "which business domain is the active company?" (livestock vs. palm).
 *
 * Detection is still by `industry` text (jwt-service does not return `business_type` and the login
 * falls back to 'ADMIN'): an explicit `business_type` wins when present, otherwise the industry text
 * decides. `companys.business_type` as a real column is technical debt (see CLAUDE.md, Rule 18).
 *
 * Used by MainLayoutComponent (theme), SidebarComponent (menu), TenantSelectorComponent and the login
 * (landing route), so the four can never disagree again.
 */

export type BusinessDomain = 'PALM' | 'LIVESTOCK' | 'UNKNOWN';

/** Minimal shape of a TenantContext / company row needed to decide the domain. */
export interface DomainBearing {
  business_type?: string | null;
  industry?: string | null;
}

export const PALM_DASHBOARD_ROUTE = '/agricultura/dashboard';
export const LIVESTOCK_DASHBOARD_ROUTE = '/ganaderia/dashboard';

/** Lowercase, trimmed and without accents ("Ganadería" -> "ganaderia"). */
function normalize(text: string | null | undefined): string {
  return (text ?? '').toString().normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().trim();
}

export function resolveBusinessDomain(tenant: DomainBearing | null | undefined): BusinessDomain {
  if (!tenant) return 'UNKNOWN';

  const businessType = normalize(tenant.business_type).toUpperCase();
  if (businessType === 'AGRICULTURE') return 'PALM';
  if (businessType === 'LIVESTOCK') return 'LIVESTOCK';

  const industry = normalize(tenant.industry);
  // Palm is checked first: it is the more specific label ("Agricultura de Precisión").
  if (industry.includes('agricultura')) return 'PALM';
  if (industry.includes('ganader')) return 'LIVESTOCK';
  return 'UNKNOWN';
}

export function isPalmDomain(tenant: DomainBearing | null | undefined): boolean {
  return resolveBusinessDomain(tenant) === 'PALM';
}

export function isLivestockDomain(tenant: DomainBearing | null | undefined): boolean {
  return resolveBusinessDomain(tenant) === 'LIVESTOCK';
}

/** Landing route of a company. Unknown domains keep the historical default (livestock). */
export function dashboardRouteFor(tenant: DomainBearing | null | undefined): string {
  return isPalmDomain(tenant) ? PALM_DASHBOARD_ROUTE : LIVESTOCK_DASHBOARD_ROUTE;
}

export function themeClassFor(tenant: DomainBearing | null | undefined): 'theme-palm' | 'theme-cattle' {
  return isPalmDomain(tenant) ? 'theme-palm' : 'theme-cattle';
}
