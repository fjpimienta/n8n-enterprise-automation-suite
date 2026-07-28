import { ProductionUnit, UppComplianceStatus } from './agro-registry.model';

/**
 * View-layer projections produced by ComplianceService's mapping step.
 * agro-registry.model.ts stays a verbatim copy of the wire contract; these
 * shapes carry the fields components should actually render.
 */

/**
 * True when grazing_surface_ha > 0. The API sends "0.00" both when the constancia
 * genuinely declares zero and when it declares no grazing surface at all — those two
 * cases are indistinguishable from the raw field alone. Consumers must branch on this
 * flag instead of testing grazing_surface_ha directly.
 */
interface GrazingSurfaceFlag {
  hasGrazingSurface: boolean;
}

export interface UppComplianceStatusView extends UppComplianceStatus, GrazingSurfaceFlag {}

export interface ProductionUnitView extends ProductionUnit, GrazingSurfaceFlag {}
