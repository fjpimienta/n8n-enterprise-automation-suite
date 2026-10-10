import { describe, it, expect } from 'vitest';
import { canCancelRequest, isSanitaryExceptionAvailable, resolveCurrentUserEmail } from './authorization-actions.util';

describe('resolveCurrentUserEmail', () => {
  it('reads the `user` claim emitted by jwt-service', () => {
    expect(resolveCurrentUserEmail({ user: 'ana@rancho.mx' })).toBe('ana@rancho.mx');
  });

  it('falls back to `email` when `user` is absent', () => {
    expect(resolveCurrentUserEmail({ email: 'ana@rancho.mx' })).toBe('ana@rancho.mx');
  });

  it('returns null for a missing payload or blank/non-string values', () => {
    expect(resolveCurrentUserEmail(null)).toBeNull();
    expect(resolveCurrentUserEmail({ user: '   ' })).toBeNull();
    expect(resolveCurrentUserEmail({ user: 42 })).toBeNull();
  });
});

describe('canCancelRequest', () => {
  const row = { estado: 'PENDIENTE' as const, solicitado_por_email: 'Ana@Rancho.mx' };

  it('allows the requester on a PENDIENTE row, case-insensitively', () => {
    expect(canCancelRequest(row, 'ana@rancho.MX')).toBe(true);
    expect(canCancelRequest(row, ' ana@rancho.mx ')).toBe(true);
  });

  it('denies a different user', () => {
    expect(canCancelRequest(row, 'otro@rancho.mx')).toBe(false);
  });

  it('denies when the current email is unknown', () => {
    expect(canCancelRequest(row, null)).toBe(false);
    expect(canCancelRequest(row, '')).toBe(false);
  });

  it('denies non-PENDIENTE rows', () => {
    for (const estado of ['APROBADO', 'RECHAZADO', 'EXPIRADO', 'CANCELADO'] as const) {
      expect(canCancelRequest({ ...row, estado }, 'ana@rancho.mx')).toBe(false);
    }
  });
});

describe('isSanitaryExceptionAvailable', () => {
  const rejected = { success: false, resultado_sp: { success: false, excepcion_disponible: true } };

  it('is true for VENTA when the dispatcher offers the exception', () => {
    expect(isSanitaryExceptionAvailable({ tipo_evento: 'VENTA' }, rejected)).toBe(true);
  });

  it('is never true for BAJA_MORTANDAD', () => {
    expect(isSanitaryExceptionAvailable({ tipo_evento: 'BAJA_MORTANDAD' }, rejected)).toBe(false);
  });

  it('is false when the exception is not available or the call succeeded', () => {
    expect(isSanitaryExceptionAvailable({ tipo_evento: 'VENTA' },
      { success: false, resultado_sp: { excepcion_disponible: false } })).toBe(false);
    expect(isSanitaryExceptionAvailable({ tipo_evento: 'VENTA' }, { success: false })).toBe(false);
    expect(isSanitaryExceptionAvailable({ tipo_evento: 'VENTA' },
      { success: true, resultado_sp: { excepcion_disponible: true } })).toBe(false);
    expect(isSanitaryExceptionAvailable({ tipo_evento: 'VENTA' }, null)).toBe(false);
  });
});
