import { ChatAttachmentsConfig } from '../interfaces/chat-config';

/** Hard upper bound for a raw attachment. The config can only lower it. */
export const MAX_ATTACHMENT_BYTES = 5 * 1024 * 1024;
export const MAX_FILE_NAME_LENGTH = 255;

export const DEFAULT_ATTACHMENT_ACCEPT: readonly string[] = [
  'image/jpeg',
  'image/png',
  'image/webp',
  'application/pdf',
  'text/xml',
  'application/xml'
];

const EXTENSION_TYPES: Readonly<Record<string, string>> = {
  xml: 'text/xml',
  pdf: 'application/pdf',
  jpg: 'image/jpeg',
  jpeg: 'image/jpeg',
  png: 'image/png',
  webp: 'image/webp'
};

// C0/C1 controls plus bidi overrides/isolates (filename spoofing, e.g. "invoice‮fdp.exe").
const UNSAFE_NAME_CHARS = /[\u0000-\u001F\u007F-\u009F‪-‮⁦-⁩]/g;

export interface ResolvedAttachmentsConfig {
  enabled: boolean;
  maxBytes: number;
  accept: readonly string[];
}

export type AttachmentCheck =
  | { ok: true; name: string; type: string; size: number }
  | { ok: false; reason: 'empty' | 'size' | 'type' };

export function resolveAttachmentsConfig(cfg?: ChatAttachmentsConfig): ResolvedAttachmentsConfig {
  const mb = typeof cfg?.maxSizeMb === 'number' && cfg.maxSizeMb > 0 ? cfg.maxSizeMb : 5;
  return {
    enabled: cfg?.enabled === true,
    maxBytes: Math.min(Math.floor(mb * 1024 * 1024), MAX_ATTACHMENT_BYTES),
    accept: (cfg?.accept ?? DEFAULT_ATTACHMENT_ACCEPT).map(t => t.toLowerCase())
  };
}

/** Display-only metadata: the server must never trust it. */
export function sanitizeFileName(name: string): string {
  const clean = Array.from(name.replace(UNSAFE_NAME_CHARS, '')).slice(0, MAX_FILE_NAME_LENGTH).join('').trim();
  return clean || 'file';
}

/**
 * Effective MIME type: `file.type` if accepted; otherwise, only when the browser reported an
 * empty or generic type, the one mapped from the extension, if accepted. Null if not allowed.
 */
export function resolveFileType(file: { name: string; type: string }, accept: readonly string[]): string | null {
  const reported = (file.type ?? '').toLowerCase();
  if (reported && accept.includes(reported)) return reported;
  if (reported && reported !== 'application/octet-stream') return null;

  const dot = file.name.lastIndexOf('.');
  const mapped = dot >= 0 ? EXTENSION_TYPES[file.name.slice(dot + 1).toLowerCase()] : undefined;
  return mapped && accept.includes(mapped) ? mapped : null;
}

export function checkAttachment(file: File, cfg: ResolvedAttachmentsConfig): AttachmentCheck {
  if (file.size === 0) return { ok: false, reason: 'empty' };
  if (file.size > cfg.maxBytes) return { ok: false, reason: 'size' };
  const type = resolveFileType(file, cfg.accept);
  if (!type) return { ok: false, reason: 'type' };
  return { ok: true, name: sanitizeFileName(file.name), type, size: file.size };
}

/** Reads the file into raw Base64 (no data-URL prefix). Callers must keep it request-scoped. */
export async function readAsBase64(file: Blob, maxBytes: number): Promise<string> {
  const bytes = new Uint8Array(await file.arrayBuffer());
  if (bytes.byteLength > maxBytes) throw new Error('Attachment exceeds the size limit');
  let binary = '';
  for (let i = 0; i < bytes.length; i += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  }
  return btoa(binary);
}
