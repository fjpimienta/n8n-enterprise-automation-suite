/**
 * Structured legal content. The wording comes verbatim from the approved Google-Docs-style draft
 * "Borrador legal Hosting3M: aviso de privacidad y condiciones de servicio" (21 de noviembre de 2026).
 * Do not paraphrase: edits to the legal wording must come from the lawyer-reviewed text.
 *
 * Inline syntax inside strings: **bold**, *italic*, `code`, [label](/internal-path).
 * Placeholders resolved from the single sources (core/business.ts, core/site.config.ts, core/consent.ts):
 * {legalName} {address} {email} {phone} {lastUpdated} {gaId} {consentKey}.
 * Editorial markers such as [VERIFICAR] or [REVISAR] left in these strings make the production build fail
 * (scripts/check-legal-markers.mjs).
 */
export type LegalBlock =
  | { readonly type: 'p'; readonly text: string }
  | { readonly type: 'ul'; readonly items: readonly string[] }
  | {
      readonly type: 'table';
      /** Accessible name of the table (rendered as a screen-reader caption). */
      readonly caption: string;
      readonly columns: readonly string[];
      /** The first cell of every row is its row header. */
      readonly rows: readonly (readonly string[])[];
    };

export interface LegalSection {
  /** Bold lead of the paragraph in the source draft, rendered as an h2. */
  readonly heading?: string;
  readonly blocks: readonly LegalBlock[];
}

export interface LegalDoc {
  readonly slug: 'privacy' | 'cookies' | 'terms';
  /** h1 of the page. */
  readonly title: string;
  readonly sections: readonly LegalSection[];
}
