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
  type: 'missing' | 'invalid' | 'ambiguous' | 'not_found';
  field: string;
  message: string;
  options?: unknown[];
  code?: string;
}

/** Values exactly as the procedure understood them (keys are those of the procedure, in Spanish). */
export type PanelLivestockPreview = Record<string, unknown>;

export interface PanelLivestockResponse {
  status: PanelLivestockStatus;
  message?: string;
  empresa?: string;
  issues?: PanelLivestockIssue[];
  warnings?: string[];
  preview?: PanelLivestockPreview;
  preview_hash?: string;
  livestock_id?: string;
  identificador?: string;
  code?: string;
  [key: string]: unknown;
}
