/**
 * Domain contracts for the SENASICA-SINIIGA regulatory registry.
 *
 * Multi-tenant rule: every entity carries idCompany. Any egress pipeline that builds a
 * payload without it must fail closed rather than fall back to a default tenant.
 *
 * Naming: the API returns snake_case (Meta-CRUD is a thin passthrough over PostgreSQL).
 * These interfaces model the wire format directly; mapping to camelCase belongs in the
 * feature service, not here.
 */

export type OrgType = 'GANADERO' | 'UNION' | 'GOBIERNO';

export type ProducerRole = 'TITULAR' | 'SOCIO' | 'REPRESENTANTE';

export type TenureType =
  | 'PRIVADA'
  | 'EJIDAL'
  | 'COMUNAL'
  | 'RENTADA'
  | 'COMODATO'
  | 'OTRA';

export type CertificateType =
  | 'PGN_UPP_REGISTRATION'
  | 'PGN_UPP_UPDATE'
  | 'PGN_PSG_UPDATE';

export type ComplianceEntityType =
  | 'COMPLIANCE_CERTIFICATE'
  | 'PRODUCTION_UNIT'
  | 'PSG_LICENSE';

export type UpdateStatus = 'OK' | 'WARNING' | 'EXPIRED' | 'UNKNOWN';

export type PsgValidityStatus = 'VALID' | 'EXPIRING_SOON' | 'EXPIRED' | 'UNKNOWN';

export type CensusSource = 'PGN_CERTIFICATE' | 'MANUAL' | 'FIELD_AGENT';

export type SurfaceRegime = 'riego' | 'temporal';

export type SurfaceConcept =
  | 'estabulado'
  | 'agostadero'
  | 'agricola'
  | 'forestal_maderable'
  | 'praderas'
  | 'cultivos_forrajeros';

/**
 * Verbatim copy of the SENASICA surface grid. Treated as evidence of record: never
 * normalized, never corrected client-side. schema_version guards against future format
 * changes on SENASICA's side.
 */
export interface SurfaceMatrix {
  schema_version: number;
  riego: Record<SurfaceConcept, number>;
  temporal: Record<SurfaceConcept, number>;
  source_note?: string;
}

/** Non-sensitive producer projection. CURP and RFC are never present on this shape. */
export interface LivestockProducer {
  id: string;
  id_company: number;
  full_name: string;
  producer_role: ProducerRole;
  contact_email: string | null;
  contact_phone: string | null;
  address_street: string | null;
  address_number: string | null;
  address_colony: string | null;
  address_locality: string | null;
  address_municipality: string | null;
  address_state: string | null;
  address_postal_code: string | null;
  is_active: boolean;
  created_at: string;
}

/**
 * Producer projection including decrypted personal data. Served only to ADMIN / OWNER and
 * only from the dedicated read model. Do not cache this shape in a signal that outlives
 * the view that needs it.
 */
export interface LivestockProducerWithPii extends LivestockProducer {
  curp: string | null;
  rfc: string | null;
}

export interface ProductionUnit {
  id: string;
  id_company: number;
  producer_id: string | null;
  /** Format EE-MMM-NNNN-SSS. First five digits encode INEGI state and municipality. */
  upp_code: string;
  ranch_name: string;
  /** Server-generated from upp_code. Read-only: writing it has no effect. */
  state_code: string;
  /** Server-generated from upp_code. Read-only: writing it has no effect. */
  municipality_code: string;
  state_name: string | null;
  municipality_name: string | null;
  locality_name: string | null;
  tenure_type: TenureType | null;
  access_directions: string | null;
  latitude: number | null;
  longitude: number | null;
  total_surface_ha: number | null;
  /** True when the constancia reports "Parcial". Changes the stocking-rate denominator. */
  is_partial_surface: boolean;
  surface_matrix: SurfaceMatrix | null;
  /** Server-computed from surface_matrix. Read-only. */
  grazing_surface_ha: number | null;
  fire_brand_patent: string | null;
  uma_registry: string | null;
  registration_date: string | null;
  last_update_at: string | null;
  is_active: boolean;
  created_at: string;
}

export interface PsgLicense {
  id: string;
  id_company: number;
  producer_id: string | null;
  /** Format EE-MMM-NNNN-Pnn. */
  psg_code: string;
  state_code: string;
  municipality_code: string;
  state_name: string | null;
  municipality_name: string | null;
  issuing_window: string | null;
  issued_at: string;
  /** Null when the constancia prints no expiry; validity is then derived server-side. */
  expires_at: string | null;
  is_active: boolean;
  created_at: string;
}

export interface ComplianceCertificate {
  id: string;
  id_company: number;
  production_unit_id: string | null;
  psg_license_id: string | null;
  certificate_type: CertificateType;
  folio: string;
  issued_at: string;
  issuing_window: string | null;
  issuing_officer: string | null;
  source_url: string | null;
  notes: string | null;
  created_at: string;
}

export interface ComplianceDocument {
  id: string;
  id_company: number;
  entity_type: ComplianceEntityType;
  entity_id: string;
  /** Opaque storage handle. Never render as a direct URL: resolve via the authenticated endpoint. */
  storage_key: string;
  original_name: string | null;
  mime_type: string;
  size_bytes: number | null;
  /** Integrity proof. Recompute on download and compare before trusting the artifact. */
  sha256_hash: string;
  uploaded_by: string | null;
  uploaded_at: string;
}

export interface LivestockCensusSnapshot {
  id: string;
  id_company: number;
  production_unit_id: string;
  certificate_id: string | null;
  snapshot_date: string;
  source: CensusSource;
  /** Declared head counts keyed by species, as printed on the constancia. */
  species_counts: Record<string, Record<string, number>>;
  total_head: number;
  breed_note: string | null;
  notes: string | null;
  created_at: string;
}

/** Read model backing the UPP compliance dashboard. All fields are server-computed. */
export interface UppComplianceStatus {
  production_unit_id: string;
  id_company: number;
  company_name: string;
  upp_code: string;
  ranch_name: string;
  state_name: string | null;
  municipality_name: string | null;
  total_surface_ha: number | null;
  is_partial_surface: boolean;
  grazing_surface_ha: number | null;
  /**
   * True when the declared total disagrees with the sum of the grid. Several real
   * constancias trip this: it is a review flag, not a data error on our side.
   */
  has_surface_inconsistency: boolean;
  registration_date: string | null;
  last_update_at: string | null;
  days_since_update: number | null;
  update_status: UpdateStatus;
  last_declared_head: number | null;
  last_census_date: string | null;
  active_head_in_system: number;
  is_active: boolean;
}

/** Read model backing the PSG validity dashboard. */
export interface PsgComplianceStatus {
  psg_license_id: string;
  id_company: number;
  company_name: string;
  psg_code: string;
  state_code: string;
  municipality_code: string;
  state_name: string | null;
  municipality_name: string | null;
  issuing_window: string | null;
  issued_at: string;
  expires_at: string | null;
  /** Resolved expiry: expires_at when present, otherwise issued_at + tenant validity window. */
  effective_expires_at: string;
  validity_status: PsgValidityStatus;
  producer_name: string | null;
  is_active: boolean;
}
