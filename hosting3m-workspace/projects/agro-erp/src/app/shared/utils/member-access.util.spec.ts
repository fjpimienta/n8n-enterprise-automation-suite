import { describe, it, expect } from 'vitest';
import type { CompanyMember, MemberFormData } from '@core/models/company-member.model';
import {
  addMemberSuccessMessage,
  buildUpdateFields,
  canEditProfile,
  gatewayErrorMessage,
  interpretAccessResponse,
  isSelf,
  resolveAddMemberResult,
  resolveUpdateMemberResult,
  UNCONFIRMED_ACCESS_MESSAGE,
  isValidEmail,
  normalizeEmail,
  roleLabel,
  validateMemberForm
} from './member-access.util';

const member = (overrides: Partial<CompanyMember> = {}): CompanyMember => ({
  id_company: 6,
  email: 'caporal@rancho.mx',
  names: 'Juan',
  lastname: 'Pérez',
  phone: '9930000000',
  role: 'EDITOR',
  is_active: true,
  account_is_active: true,
  profile_managed_here: true,
  created_at: '2026-10-01T00:00:00',
  ...overrides
});

const form = (overrides: Partial<MemberFormData> = {}): MemberFormData => ({
  email: 'nuevo@rancho.mx',
  names: 'Nuevo',
  lastname: '',
  phone: '',
  role: 'EDITOR',
  password: 'password123',
  ...overrides
});

describe('normalizeEmail / isValidEmail', () => {
  it('trims and lowercases', () => {
    expect(normalizeEmail('  Ana.Lopez@Rancho.MX ')).toBe('ana.lopez@rancho.mx');
    expect(normalizeEmail(null)).toBe('');
  });

  it('rejects malformed values such as a trailing "|"', () => {
    expect(isValidEmail('12095038@gmail.com|')).toBe(false);
    expect(isValidEmail('sin-arroba.com')).toBe(false);
    expect(isValidEmail('a@b')).toBe(false);
    expect(isValidEmail('')).toBe(false);
  });

  it('accepts normal addresses', () => {
    expect(isValidEmail('12095038@gmail.com')).toBe(true);
    expect(isValidEmail('juan.carlos+campo@mi-rancho.com.mx')).toBe(true);
  });
});

describe('roleLabel', () => {
  it('labels CUSTOMER as read-only', () => {
    expect(roleLabel('CUSTOMER')).toBe('Solo lectura');
    expect(roleLabel('editor')).toBe('Operador / Caporal');
    expect(roleLabel('OWNER')).toBe('OWNER');
  });
});

describe('canEditProfile / isSelf', () => {
  it('allows a new person and exclusive members', () => {
    expect(canEditProfile(null, 'admin@rancho.mx')).toBe(true);
    expect(canEditProfile(member(), 'admin@rancho.mx')).toBe(true);
  });

  it('blocks shared members unless it is the current user', () => {
    const shared = member({ profile_managed_here: false });
    expect(canEditProfile(shared, 'admin@rancho.mx')).toBe(false);
    expect(canEditProfile(shared, ' CAPORAL@rancho.mx ')).toBe(true);
  });

  it('detects self case-insensitively', () => {
    expect(isSelf(member(), 'Caporal@Rancho.mx')).toBe(true);
    expect(isSelf(member(), null)).toBe(false);
  });
});

describe('validateMemberForm', () => {
  it('requires a valid email, name and an 8+ char password for a new person', () => {
    expect(validateMemberForm(form({ email: 'x@y.com|' }), null, null)).toMatch(/Correo/);
    expect(validateMemberForm(form({ names: '  ' }), null, null)).toMatch(/nombre/);
    expect(validateMemberForm(form({ password: '1234' }), null, null)).toMatch(/8 caracteres/);
    expect(validateMemberForm(form(), null, null)).toBeNull();
  });

  it('lets an edit keep the current password (empty) but not set a short one', () => {
    expect(validateMemberForm(form({ password: '' }), member(), 'admin@rancho.mx')).toBeNull();
    expect(validateMemberForm(form({ password: 'short' }), member(), 'admin@rancho.mx')).toMatch(/8 caracteres/);
  });

  it('skips profile checks for a shared member edited by someone else', () => {
    const shared = member({ profile_managed_here: false });
    expect(validateMemberForm(form({ names: '', password: 'x' }), shared, 'admin@rancho.mx')).toBeNull();
  });
});

describe('buildUpdateFields', () => {
  it('sends null profile fields and no password for a shared member', () => {
    const fields = buildUpdateFields(form({ names: 'Otro', password: 'password123', role: 'CUSTOMER' }),
      member({ profile_managed_here: false }), 'admin@rancho.mx');
    expect(fields).toEqual({ email: 'caporal@rancho.mx', names: null, lastname: null, phone: null, role: 'CUSTOMER', password: '' });
  });

  it('sends trimmed profile fields for an exclusive member, keyed by the stored email', () => {
    const fields = buildUpdateFields(form({ email: 'IGNORED@x.com', names: ' Juan ', lastname: ' P ', phone: ' 99 ' }),
      member(), 'admin@rancho.mx');
    expect(fields).toEqual({ email: 'caporal@rancho.mx', names: 'Juan', lastname: 'P', phone: '99', role: 'EDITOR', password: 'password123' });
  });
});

describe('interpretAccessResponse / resolveAddMemberResult (fail-closed)', () => {
  const ok = (data: Record<string, unknown>) => ({ error: false, operation: 'call_sp', message: 'Ejecución satisfactoria', data });

  it('regression: a response without explicit SP success is RED, never "ya tenía cuenta"', () => {
    // Seen locally with a Build Query lacking the sp_access_add_user config: nothing was written,
    // the response carried no `error: true` and no `created_account`, and the UI showed green.
    const notConfirmed = [
      null, undefined, '', 'Workflow was started', [],
      {},
      { message: 'Error in workflow' },
      { code: 0, message: 'No hay configuración de parámetros para el procedimiento sp_access_add_user' },
      { error: false, data: null },
      { error: false, data: [] },
      { error: false, data: {} },
      { error: false, data: { success: false } },
      { data: { success: true, created_account: true } }, // `error` missing
      { error: 'false', data: { success: true, created_account: true } }
    ];
    for (const res of notConfirmed) {
      const result = resolveAddMemberResult(res);
      expect(result.ok, JSON.stringify(res)).toBe(false);
      expect(result.message).not.toMatch(/ya tenía cuenta/);
      expect(result.message).toBe(UNCONFIRMED_ACCESS_MESSAGE);
    }
  });

  it('shows the SP message in red for HTTP 200 with error: true', () => {
    expect(resolveAddMemberResult({ error: true, operation: 'call_sp', message: 'Esta persona ya pertenece a la empresa', data: null }))
      .toEqual({ ok: false, message: 'Esta persona ya pertenece a la empresa' });
    expect(resolveAddMemberResult({ error: true, data: null }))
      .toEqual({ ok: false, message: UNCONFIRMED_ACCESS_MESSAGE });
  });

  it('is RED when the SP reports success but created_account is not a boolean', () => {
    for (const created of [undefined, null, 'false', 0, 1]) {
      expect(resolveAddMemberResult(ok({ success: true, email: 'x@y.mx', created_account: created })))
        .toEqual({ ok: false, message: UNCONFIRMED_ACCESS_MESSAGE });
    }
  });

  it('is GREEN only for an explicit SP success with a boolean created_account', () => {
    expect(resolveAddMemberResult(ok({ success: true, email: 'x@y.mx', created_account: true })))
      .toEqual({ ok: true, message: 'Personal registrado en la empresa.' });
    const existing = resolveAddMemberResult(ok({ success: true, email: 'x@y.mx', created_account: false }));
    expect(existing.ok).toBe(true);
    expect(existing.message).toMatch(/ya tenía cuenta/);
  });

  it('applies the same rule to edit and activate/deactivate responses', () => {
    expect(resolveUpdateMemberResult(ok({ success: true, role_changed: true }))).toEqual({ ok: true, message: 'Cambios guardados.' });
    expect(resolveUpdateMemberResult(null).ok).toBe(false);
    expect(resolveUpdateMemberResult({ message: 'Error in workflow' })).toEqual({ ok: false, message: UNCONFIRMED_ACCESS_MESSAGE });
    expect(interpretAccessResponse(ok({ success: true, changed: true, account_is_active: false })))
      .toEqual({ ok: true, data: { success: true, changed: true, account_is_active: false } });
    expect(interpretAccessResponse({ error: false }).ok).toBe(false);
  });
});

describe('messages', () => {
  it('distinguishes a new account from an existing one, and only for explicit booleans', () => {
    expect(addMemberSuccessMessage(true)).toBe('Personal registrado en la empresa.');
    expect(addMemberSuccessMessage(false)).toMatch(/ya tenía cuenta/);
    expect(addMemberSuccessMessage(undefined)).toBeNull();
    expect(addMemberSuccessMessage(null)).toBeNull();
  });

  it('prefers the gateway/SP message and falls back otherwise', () => {
    expect(gatewayErrorMessage({ error: true, message: 'Un ADMIN no puede cambiar su propio rol' }, 'x'))
      .toBe('Un ADMIN no puede cambiar su propio rol');
    expect(gatewayErrorMessage({ error: { message: 'Prohibido' } }, 'x')).toBe('Prohibido');
    expect(gatewayErrorMessage(null, 'Sin conexión')).toBe('Sin conexión');
  });
});
