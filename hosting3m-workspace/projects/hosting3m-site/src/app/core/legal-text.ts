import { BUSINESS, BUSINESS_ADDRESS_LINE, LEGAL_LAST_UPDATED } from './business';
import { STORAGE_KEY } from './consent';
import { SITE } from './site.config';

/** Placeholders usable inside the legal data files; every value comes from its single source. */
export const LEGAL_PLACEHOLDERS: Readonly<Record<string, string>> = {
  legalName: BUSINESS.legalName,
  address: BUSINESS_ADDRESS_LINE,
  email: BUSINESS.email,
  phone: BUSINESS.phone,
  lastUpdated: LEGAL_LAST_UPDATED,
  gaId: SITE.ga4Id.replace(/^G-/, ''),
  consentKey: STORAGE_KEY,
};

export function fillPlaceholders(text: string): string {
  return text.replace(/\{(\w+)\}/g, (whole, key: string) => LEGAL_PLACEHOLDERS[key] ?? whole);
}

export interface InlineSegment {
  readonly kind: 'text' | 'bold' | 'italic' | 'code' | 'link';
  readonly text: string;
  readonly href?: string;
}

const INLINE = /\*\*(.+?)\*\*|\*(.+?)\*|`(.+?)`|\[(.+?)\]\((\/[^)\s]*)\)/g;

/** Splits a string with the small inline syntax into safe segments (rendered with bindings, never innerHTML). */
export function parseInline(raw: string): InlineSegment[] {
  const text = fillPlaceholders(raw);
  const out: InlineSegment[] = [];
  let last = 0;
  for (const m of text.matchAll(INLINE)) {
    if (m.index > last) out.push({ kind: 'text', text: text.slice(last, m.index) });
    if (m[1] !== undefined) out.push({ kind: 'bold', text: m[1] });
    else if (m[2] !== undefined) out.push({ kind: 'italic', text: m[2] });
    else if (m[3] !== undefined) out.push({ kind: 'code', text: m[3] });
    else out.push({ kind: 'link', text: m[4], href: m[5] });
    last = m.index + m[0].length;
  }
  if (last < text.length) out.push({ kind: 'text', text: text.slice(last) });
  return out;
}
