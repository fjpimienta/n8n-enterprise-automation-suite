/**
 * Maps a failed chat HTTP call to the message shown to the user.
 *
 * Interrupted: the request may have been partly processed (proxy timeout,
 * dropped connection, n8n restart or workflow error without a reply).
 * The text tells the user to check before repeating the operation.
 */
export type ChatErrorKind = 'interrupted' | 'unexpected';

export const CHAT_INTERRUPTED_MESSAGE =
  '⚠️ La operación se interrumpió. Puede que no se haya completado: revisa antes de repetirla. Intenta de nuevo en un minuto.';

export const CHAT_UNEXPECTED_MESSAGE =
  '⚠️ Ocurrió un error inesperado. Intenta de nuevo en un minuto.';

// 0 = network error or dropped connection; 5xx = n8n/proxy; 52x = Cloudflare origin errors.
const INTERRUPTED_STATUSES: ReadonlySet<number> = new Set([
  0, 500, 502, 503, 504, 520, 521, 522, 523, 524,
]);

export function classifyChatHttpError(err: unknown): ChatErrorKind {
  const status = (err as { status?: unknown } | null | undefined)?.status;
  return typeof status === 'number' && INTERRUPTED_STATUSES.has(status)
    ? 'interrupted'
    : 'unexpected';
}

export function chatErrorMessage(err: unknown): string {
  return classifyChatHttpError(err) === 'interrupted'
    ? CHAT_INTERRUPTED_MESSAGE
    : CHAT_UNEXPECTED_MESSAGE;
}
