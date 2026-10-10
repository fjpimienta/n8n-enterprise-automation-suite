import type { PendingAuthorization, ResolveAuthorizationResult } from '@core/models/pending-authorization.model';

/**
 * Email of the authenticated user from the decoded JWT held by core-auth's AuthService.
 * jwt-service signs the email under the `user` claim, not `email` (core-auth's UserPayload
 * does not match the real token), so `user` is read first and `email` kept as a fallback in
 * case that mismatch is fixed upstream.
 */
export function resolveCurrentUserEmail(payload: { user?: unknown; email?: unknown } | null | undefined): string | null {
  const raw = payload?.user ?? payload?.email;
  return typeof raw === 'string' && raw.trim() !== '' ? raw.trim() : null;
}

/**
 * UI convenience only: shows "Cancelar solicitud" on PENDIENTE rows created by the current
 * user. The real rule (requester-only, PENDIENTE, not expired) is enforced by
 * `sp_cancelar_autorizacion`.
 */
export function canCancelRequest(
  row: Pick<PendingAuthorization, 'estado' | 'solicitado_por_email'>,
  currentUserEmail: string | null | undefined
): boolean {
  if (row.estado !== 'PENDIENTE' || !currentUserEmail || !row.solicitado_por_email) return false;
  return row.solicitado_por_email.trim().toLowerCase() === currentUserEmail.trim().toLowerCase();
}

/**
 * True when an APROBADO attempt on a VENTA was rejected by the sanitary rule and the backend
 * reports that an approval with sanitary exception is possible. Never true for BAJA_MORTANDAD.
 */
export function isSanitaryExceptionAvailable(
  row: Pick<PendingAuthorization, 'tipo_evento'>,
  result: Partial<ResolveAuthorizationResult> | null | undefined
): boolean {
  return row.tipo_evento === 'VENTA'
    && result?.success === false
    && result.resultado_sp?.excepcion_disponible === true;
}
