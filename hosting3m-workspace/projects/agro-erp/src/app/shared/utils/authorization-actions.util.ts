import type { PendingAuthorization, ResolveAuthorizationResult } from '@core/models/pending-authorization.model';
import { isAuthorizationExpired } from './authorization-deadline.util';

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

/**
 * Backend messages that mean the request can no longer be acted on (expired, already resolved
 * or cancelled), e.g. "La solicitud ya venció…", "La solicitud ya fue resuelta…",
 * "La solicitud ya no está pendiente…". Accent-insensitive.
 */
export function isStaleRequestMessage(message: string | null | undefined): boolean {
  return /venci[oó]|ya fue|no est[aá] pendiente/i.test(message ?? '');
}

/** Result of one single-row action (approve / reject / cancel) as the modal needs it. */
export type ActionOutcome =
  | { kind: 'success'; message: string }
  | { kind: 'stale'; message: string }
  | { kind: 'error'; message: string };

/** `error:true` from the gateway (HTTP 200): a stale-request message is not a fixable error. */
export function outcomeForGatewayError(message: string | null | undefined): ActionOutcome {
  const text = (message ?? '').trim() || 'El servidor reportó un error al procesar la solicitud.';
  return isStaleRequestMessage(text) ? { kind: 'stale', message: text } : { kind: 'error', message: text };
}

export interface ModalTransition {
  closeModal: boolean;
  reloadList: boolean;
  /** Shown inside the still-open modal (Tabler alert-danger). */
  inlineError: string | null;
  toast: { type: 'success' | 'info'; text: string } | null;
}

/**
 * What the cancel/reject/approve modal does with an outcome:
 *  - error: stays open, keeps the typed reason, shows the message inline;
 *  - stale (expired / already resolved / cancelled): closes, toasts the message, reloads;
 *  - success: closes, toasts the success text, reloads.
 */
export function modalTransitionFor(outcome: ActionOutcome): ModalTransition {
  switch (outcome.kind) {
    case 'error':
      return { closeModal: false, reloadList: false, inlineError: outcome.message, toast: null };
    case 'stale':
      return { closeModal: true, reloadList: true, inlineError: null, toast: { type: 'info', text: outcome.message } };
    case 'success':
      return { closeModal: true, reloadList: true, inlineError: null, toast: { type: 'success', text: outcome.message } };
  }
}

/** Batch approval only takes pending VENTA rows that have not expired yet. */
export function isSelectableForBatch(
  row: Pick<PendingAuthorization, 'tipo_evento' | 'estado' | 'fecha_solicitud'>,
  nowMs: number
): boolean {
  return row.tipo_evento === 'VENTA' && row.estado === 'PENDIENTE' && !isAuthorizationExpired(row.fecha_solicitud, nowMs);
}
