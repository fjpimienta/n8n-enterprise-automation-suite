import type { AccessProcedureResult, CompanyMember, MemberFormData, MemberRole } from '@core/models/company-member.model';

/**
 * UI-side mirror of the rules enforced by sp_access_* (migration 073). These helpers only shape the
 * form and the messages; the database functions remain the source of truth and reject anything else.
 */

export interface RoleOption {
  value: MemberRole;
  label: string;
  description: string;
}

export const MEMBER_ROLE_OPTIONS: readonly RoleOption[] = [
  {
    value: 'ADMIN',
    label: 'Administrador',
    description: 'Gestiona el personal, aprueba ventas y bajas por muerte y ve la información financiera.'
  },
  {
    value: 'EDITOR',
    label: 'Operador / Caporal',
    description: 'Registra todos los eventos del hato; las ventas y bajas por muerte requieren aprobación de un Administrador.'
  },
  {
    value: 'CUSTOMER',
    label: 'Solo lectura',
    description: 'Consulta la información de la empresa; no registra eventos.'
  }
];

export function roleLabel(role: string | null | undefined): string {
  const option = MEMBER_ROLE_OPTIONS.find(o => o.value === (role ?? '').toUpperCase());
  return option ? option.label : (role || 'Sin rol');
}

/** Same normalization as fn_normalize_email: trim + lowercase. */
export function normalizeEmail(raw: string | null | undefined): string {
  return (raw ?? '').trim().toLowerCase();
}

/** Same pattern as fn_is_valid_email (expects a normalized value). Rejects junk such as a trailing "|". */
const EMAIL_PATTERN = /^[a-z0-9._%+-]+@[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)*\.[a-z]{2,}$/;

export function isValidEmail(email: string): boolean {
  return email.length <= 255 && EMAIL_PATTERN.test(email);
}

export const MIN_PASSWORD_LENGTH = 8;

export function sameEmail(a: string | null | undefined, b: string | null | undefined): boolean {
  return !!a && !!b && normalizeEmail(a) === normalizeEmail(b);
}

/** Global profile fields (names/phone/password) are editable for exclusive members, or by the person themself. */
export function canEditProfile(member: CompanyMember | null, currentUserEmail: string | null): boolean {
  if (!member) return true; // new person
  return member.profile_managed_here || sameEmail(member.email, currentUserEmail);
}

/** An ADMIN can neither deactivate nor change the role of their own membership. */
export function isSelf(member: CompanyMember, currentUserEmail: string | null): boolean {
  return sameEmail(member.email, currentUserEmail);
}

/** Returns the first validation error of the form, or null when it can be sent. */
export function validateMemberForm(
  data: MemberFormData,
  member: CompanyMember | null,
  currentUserEmail: string | null
): string | null {
  if (!member) {
    if (!isValidEmail(normalizeEmail(data.email))) return 'Correo electrónico inválido.';
  }
  if (!MEMBER_ROLE_OPTIONS.some(o => o.value === data.role)) return 'Selecciona un rol.';

  if (canEditProfile(member, currentUserEmail)) {
    if (!data.names?.trim()) return 'El nombre es obligatorio.';
    const password = data.password ?? '';
    if (!member && password.length < MIN_PASSWORD_LENGTH) {
      return `La contraseña inicial debe tener al menos ${MIN_PASSWORD_LENGTH} caracteres.`;
    }
    if (member && password !== '' && password.length < MIN_PASSWORD_LENGTH) {
      return `La contraseña debe tener al menos ${MIN_PASSWORD_LENGTH} caracteres.`;
    }
  }
  return null;
}

/**
 * Fields sent to sp_access_update_member. When the profile is not editable here, names/lastname/phone
 * go as null ("keep current") and the password empty, so the SP never sees a profile change.
 */
export function buildUpdateFields(
  data: MemberFormData,
  member: CompanyMember,
  currentUserEmail: string | null
): { email: string; names: string | null; lastname: string | null; phone: string | null; role: MemberRole; password: string } {
  const editable = canEditProfile(member, currentUserEmail);
  return {
    email: member.email,
    names: editable ? data.names.trim() : null,
    lastname: editable ? (data.lastname ?? '').trim() : null,
    phone: editable ? (data.phone ?? '').trim() : null,
    role: data.role,
    password: editable ? (data.password ?? '') : ''
  };
}

export type AccessOutcome =
  | { ok: true; data: AccessProcedureResult }
  | { ok: false; message: string };

export const UNCONFIRMED_ACCESS_MESSAGE =
  'El servidor no confirmó la operación. Revisa la lista antes de reintentar.';

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

/**
 * Fail-closed reading of a call_sp response from sp_access_*. Only an explicit success counts:
 * `error === false` AND `data.success === true` (the jsonb the SP returns). Anything else (HTTP 200
 * with `error: true`, an empty/null body, an n8n failure payload without `error`, a missing `data`)
 * is an error, never a silent success.
 */
export function interpretAccessResponse(res: unknown): AccessOutcome {
  if (!isRecord(res)) return { ok: false, message: UNCONFIRMED_ACCESS_MESSAGE };
  if (res['error'] !== false || !isRecord(res['data']) || res['data']['success'] !== true) {
    // The SP/gateway message is shown only when the gateway explicitly flags the error; any other
    // payload (e.g. an n8n failure text) gets the generic "not confirmed" message.
    const message = res['error'] === true ? gatewayErrorMessage(res, UNCONFIRMED_ACCESS_MESSAGE) : UNCONFIRMED_ACCESS_MESSAGE;
    return { ok: false, message };
  }
  return { ok: true, data: res['data'] as unknown as AccessProcedureResult };
}

/**
 * Success message after sp_access_add_user. "Ya tenía cuenta" only when the SP explicitly returns
 * `created_account: false`; anything that is not a boolean returns null (the caller shows an error).
 */
export function addMemberSuccessMessage(createdAccount: unknown): string | null {
  if (createdAccount === true) return 'Personal registrado en la empresa.';
  if (createdAccount === false) {
    return 'La persona ya tenía cuenta: se agregó a esta empresa con el rol elegido. Su nombre y contraseña no se modificaron.';
  }
  return null;
}

/**
 * Full decision of the "Registrar Personal" flow from the raw gateway response: green only for an
 * explicit SP success with a boolean `created_account`; everything else is red.
 */
export function resolveAddMemberResult(res: unknown): { ok: boolean; message: string } {
  const outcome = interpretAccessResponse(res);
  if (!outcome.ok) return { ok: false, message: outcome.message };
  const message = addMemberSuccessMessage(outcome.data.created_account);
  return message ? { ok: true, message } : { ok: false, message: UNCONFIRMED_ACCESS_MESSAGE };
}

/** Same fail-closed decision for the edit flow (sp_access_update_member). */
export function resolveUpdateMemberResult(res: unknown): { ok: boolean; message: string } {
  const outcome = interpretAccessResponse(res);
  return outcome.ok ? { ok: true, message: 'Cambios guardados.' } : { ok: false, message: outcome.message };
}

/**
 * Message of a gateway call. HTTP 200 with `error: true` (MetaCRUD Silent Error Shield) carries the
 * SP's own message; a failed HTTP call may carry the gateway's `{ message }` body.
 */
export function gatewayErrorMessage(resOrError: any, fallback: string): string {
  const message = resOrError?.message ?? resOrError?.error?.message;
  return typeof message === 'string' && message.trim() ? message.trim() : fallback;
}
