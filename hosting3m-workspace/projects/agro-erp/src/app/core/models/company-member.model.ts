/** Roles a company ADMIN can assign (user_companies.role). OWNER exists in the CHECK but is not assignable here. */
export type MemberRole = 'ADMIN' | 'EDITOR' | 'CUSTOMER';

/**
 * Row of `vw_company_members` (gateway model `company_members`, migration 073). Never carries the
 * password. `profile_managed_here = false` means the person also belongs to another company: their
 * names/phone/password are read-only here (which company is deliberately not revealed).
 */
export interface CompanyMember {
  id_company: number;
  email: string;
  names: string;
  lastname: string | null;
  phone: string | null;
  role: MemberRole | 'OWNER';
  /** This company's membership (user_companies.is_active; NULL arrives as false). */
  is_active: boolean;
  /** Global account flag (users.is_active), used by WhatsApp / Web Chat. Not editable from a company. */
  account_is_active: boolean;
  profile_managed_here: boolean;
  created_at: string;
}

/** Data captured by the Personal UPP form. */
export interface MemberFormData {
  email: string;
  names: string;
  lastname: string;
  phone: string;
  role: MemberRole;
  password: string;
}

/** Result jsonb of sp_access_add_user / sp_access_update_member / sp_access_set_active. */
export interface AccessProcedureResult {
  success: boolean;
  email: string;
  role?: MemberRole;
  created_account?: boolean;
  password_applied?: boolean;
  role_changed?: boolean;
  profile_updated?: boolean;
  is_active?: boolean;
  changed?: boolean;
  account_is_active?: boolean;
}
