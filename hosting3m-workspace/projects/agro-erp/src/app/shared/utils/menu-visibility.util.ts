/**
 * Which sidebar entries the active company sees. Domain from business-domain.util; role is the role of the
 * ACTIVE company (tenantService.activeTenant()?.role), never the JWT role.
 *
 * - Palm companies never see livestock entries, and livestock companies never see palm entries.
 * - Unknown domains keep the historical behavior for configuration (livestock catalogs shown to ADMIN).
 * - A section title is shown only when at least one of its entries is visible.
 */
import { DomainBearing, resolveBusinessDomain } from './business-domain.util';

export interface MenuTenant extends DomainBearing {
  role?: string | null;
}

export interface MenuVisibility {
  livestockIntelligence: boolean;
  palmIntelligence: boolean;
  palmAdministration: boolean;
  /** "Gastos": capture for ADMIN / OWNER / EDITOR; balance and catalog only ADMIN / OWNER (inside the screen). */
  palmExpenses: boolean;
  /** Empresas, Personal: shared by both domains. */
  sharedConfig: boolean;
  /** Catálogo de Raza, Etapas de Vida, Precios de referencia, Autorizaciones Pendientes. */
  livestockConfig: boolean;
  intelligenceSection: boolean;
  configSection: boolean;
  personalLabel: 'Personal' | 'Personal UPP';
}

export function menuVisibility(tenant: MenuTenant | null | undefined): MenuVisibility {
  const domain = resolveBusinessDomain(tenant);
  const role = (tenant?.role ?? '').toUpperCase();
  const isAdmin = role === 'ADMIN';
  const palm = domain === 'PALM';

  const livestockIntelligence = domain === 'LIVESTOCK';
  const palmIntelligence = palm;
  const palmAdministration = palm && (role === 'ADMIN' || role === 'OWNER');
  const palmExpenses = palm && (role === 'ADMIN' || role === 'OWNER' || role === 'EDITOR');
  const sharedConfig = isAdmin;
  const livestockConfig = isAdmin && !palm;

  return {
    livestockIntelligence,
    palmIntelligence,
    palmAdministration,
    palmExpenses,
    sharedConfig,
    livestockConfig,
    intelligenceSection: livestockIntelligence || palmIntelligence,
    configSection: sharedConfig || livestockConfig,
    personalLabel: palm ? 'Personal' : 'Personal UPP',
  };
}
