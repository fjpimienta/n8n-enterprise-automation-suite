/**
 * Types for the web panel livestock registration procedure (`sp_register_livestock_panel`,
 * migration 102), reached through the Meta-CRUD gateway model `register_livestock_panel`
 * (migration 103, `call_sp`).
 *
 * Every input value travels as a string: the procedure receives text. Numeric values coming back
 * from the gateway may also be strings — parse explicitly.
 */

/** Form data of a panel registration. Empty values are sent as `''`. */
export interface PanelLivestockInput {
  upp?: string;
  lot?: string;
  species?: string;
  category?: string;
  business_model?: string;
  ear_tag?: string;
  fire_number?: string;
  electronic_rfid?: string;
  /** Decimal comma or point; normalised by the service before sending. */
  weight_kg?: string | number;
  birth_date?: string;
  origin_upp?: string;
  tb_test_date?: string;
  br_test_date?: string;
  notes?: string;
}

/** Options of a call. Confirmation needs the hash of the preview the user has just seen. */
export interface PanelLivestockOptions {
  confirm?: boolean;
  previewHash?: string;
  forceDuplicate?: boolean;
}

export type PanelLivestockStatus =
  | 'preview'
  | 'preview_required'
  | 'recorded'
  | 'need_info'
  | 'duplicate'
  | 'duplicate_other_company'
  | 'exists_without_upp'
  | 'duplicate_recent'
  | 'forbidden'
  | 'palm'
  | 'invalid';

export const PANEL_LIVESTOCK_STATUSES: readonly PanelLivestockStatus[] = [
  'preview', 'preview_required', 'recorded', 'need_info', 'duplicate', 'duplicate_other_company',
  'exists_without_upp', 'duplicate_recent', 'forbidden', 'palm', 'invalid'
];

export interface PanelLivestockIssue {
  /** Same value as `type` in the validation helpers; kept because the procedure returns both. */
  status?: string;
  type: 'missing' | 'invalid' | 'ambiguous' | 'not_found';
  field: string;
  message: string;
  options?: unknown[];
  code?: string;
}

/**
 * Warning types returned today: `fire_number_match` (ear tag also used as a fire number; migration 099, with an
 * `animals` list), `fire_number_repeated`, `no_official_tag`, `tb_missing_or_expired`, `br_missing_or_expired`
 * (migration 102). A new type must not break the UI, so the union also accepts any string.
 */
export type KnownPanelWarningType =
  | 'fire_number_match'
  | 'fire_number_repeated'
  | 'no_official_tag'
  | 'tb_missing_or_expired'
  | 'br_missing_or_expired';

/** A warning is an object, never text: show `message` and use `field` to point at the control. */
export interface PanelLivestockWarning {
  type: KnownPanelWarningType | (string & {});
  field?: string;
  message: string;
  [key: string]: unknown;
}

/** Values exactly as the procedure understood them (keys are those of the procedure, in Spanish). */
export type PanelLivestockPreview = Record<string, unknown>;

export interface PanelLivestockResponse {
  status: PanelLivestockStatus;
  message?: string;
  empresa?: string;
  issues?: PanelLivestockIssue[];
  warnings?: PanelLivestockWarning[];
  preview?: PanelLivestockPreview;
  preview_hash?: string;
  livestock_id?: string;
  identificador?: string;
  code?: string;
  /** Duplicate answers: the identifier that collided and the field it was typed in. */
  arete?: string;
  campo?: string;
  [key: string]: unknown;
}
