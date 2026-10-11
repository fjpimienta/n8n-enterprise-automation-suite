import { describe, it, expect } from 'vitest';
import {
  canCancelRequest,
  isSanitaryExceptionAvailable,
  isSelectableForBatch,
  modalTransitionFor,
  outcomeForGatewayError,
  resolveCurrentUserEmail
} from './authorization-actions.util';

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

describe('modalTransitionFor + outcomeForGatewayError (cancel / reject / approve modal)', () => {
  it('error:true keeps the modal open with the backend message inline, no reload', () => {
    const t = modalTransitionFor(outcomeForGatewayError('Solo quien creó la solicitud puede cancelarla'));
    expect(t).toEqual({
      closeModal: false,
      reloadList: false,
      inlineError: 'Solo quien creó la solicitud puede cancelarla',
      toast: null
    });
  });

  it('an expired message closes the modal, toasts it and reloads the list', () => {
    const message = 'La solicitud ya venció (era del día 2026-10-09); no puede cancelarse';
    const t = modalTransitionFor(outcomeForGatewayError(message));
    expect(t.closeModal).toBe(true);
    expect(t.reloadList).toBe(true);
    expect(t.inlineError).toBeNull();
    expect(t.toast).toEqual({ type: 'info', text: message });
  });

  it('already resolved / no longer pending messages are stale too', () => {
    expect(outcomeForGatewayError('La solicitud ya fue resuelta previamente (estado actual: APROBADO)').kind).toBe('stale');
    expect(outcomeForGatewayError('La solicitud ya no está pendiente (estado actual: CANCELADO)').kind).toBe('stale');
    expect(outcomeForGatewayError('LA SOLICITUD YA NO ESTA PENDIENTE').kind).toBe('stale');
  });

  it('an empty error message still keeps the modal open with a generic text', () => {
    const t = modalTransitionFor(outcomeForGatewayError(''));
    expect(t.closeModal).toBe(false);
    expect(t.inlineError).toBeTruthy();
  });

  it('success closes, toasts the success text and reloads', () => {
    expect(modalTransitionFor({ kind: 'success', message: 'Solicitud cancelada' })).toEqual({
      closeModal: true, reloadList: true, inlineError: null, toast: { type: 'success', text: 'Solicitud cancelada' }
    });
  });
});

describe('isSelectableForBatch', () => {
  // Requested 2026-10-09 13:52 CDMX (19:52 UTC) -> valid until 2026-10-09 23:59:59.999 CDMX
  // (2026-10-10 05:59:59.999 UTC); expired from 2026-10-10 00:00 CDMX (06:00 UTC) on.
  const sale = { tipo_evento: 'VENTA' as const, estado: 'PENDIENTE' as const, fecha_solicitud: '2026-10-09T19:52:00' };
  const beforeDeadline = Date.parse('2026-10-10T05:59:00Z');
  const atDeadline = Date.parse('2026-10-10T06:00:00Z');

  it('takes a pending VENTA before its deadline', () => {
    expect(isSelectableForBatch(sale, beforeDeadline)).toBe(true);
  });

  it('never takes an expired row (from the deadline on)', () => {
    expect(isSelectableForBatch(sale, atDeadline)).toBe(false);
    expect(isSelectableForBatch(sale, atDeadline + 86_400_000)).toBe(false);
  });

  it('never takes mortality requests or non-pending rows', () => {
    expect(isSelectableForBatch({ ...sale, tipo_evento: 'BAJA_MORTANDAD' }, beforeDeadline)).toBe(false);
    expect(isSelectableForBatch({ ...sale, estado: 'CANCELADO' }, beforeDeadline)).toBe(false);
  });
});
