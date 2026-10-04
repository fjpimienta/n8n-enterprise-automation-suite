/**
 * Lot (`production_unit_lots`, migration 050): a physically distinct parcel inside one
 * registered UPP. Not a paddock (`production_unit_paddocks`) — those are out of scope here.
 *
 * DB constraints mirrored by the admin form (the database enforces them regardless):
 *   - `lessor_name` may only be set when `tenure_type = 'RENTADA'`.
 *   - `lot_name` is unique per UPP, case-insensitive, among ACTIVE lots only
 *     (`uq_lot_name_per_unit`) — deactivating a lot frees its name.
 *   - Lots are never physically deleted: the Meta-CRUD model has no DELETE op.
 */
export type LotTenureType = 'PROPIO' | 'RENTADA' | 'COMODATO' | 'OTRA';

export const LOT_TENURE_OPTIONS: ReadonlyArray<{ value: LotTenureType; label: string }> = [
  { value: 'PROPIO', label: 'Propio' },
  { value: 'RENTADA', label: 'Rentada' },
  { value: 'COMODATO', label: 'Comodato' },
  { value: 'OTRA', label: 'Otra' },
];

export interface ProductionUnitLot {
  id: string;
  idCompany: number;
  productionUnitId: string;
  lotName: string;
  tenureType: LotTenureType;
  lessorName: string | null;
  locationNotes: string | null;
  isActive: boolean;
  notes: string | null;
  createdAt: string;
  /**
   * Live head assigned to this lot, derived from `vw_cattle_kpi` by
   * (`production_unit_id`, `lot_name`) because `lot_id` is not exposed by any Meta-CRUD
   * model yet. `null` when the count is ambiguous (another lot in the same UPP shares
   * the name, e.g. a deactivated lot whose name was reused).
   */
  assignedLivestockCount?: number | null;
}

export interface CreateProductionUnitLotPayload {
  productionUnitId: string;
  lotName: string;
  tenureType: LotTenureType;
  lessorName?: string;
  locationNotes?: string;
  notes?: string;
}

export type UpdateProductionUnitLotPayload = Partial<CreateProductionUnitLotPayload> & {
  isActive?: boolean;
};

/** Minimal UPP shape the lots admin needs (`production_units`). */
export interface ProductionUnitSummary {
  id: string;
  idCompany: number;
  uppCode: string;
  ranchName: string;
  stateName: string | null;
  municipalityName: string | null;
  localityName: string | null;
  isActive: boolean;
  registryStatus: string | null;
}

/** Editable identification fields of an official UPP (`production_units`). */
export interface UpdateProductionUnitPayload {
  ranchName: string;
  uppCode: string;
  stateName?: string | null;
  municipalityName?: string | null;
  localityName?: string | null;
}

/** Case-insensitive key matching the `upper(lot_name)` expression of `uq_lot_name_per_unit`. */
export function lotNameKey(name: string | null | undefined): string {
  return (name ?? '').trim().toUpperCase();
}
