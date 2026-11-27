/**
 * Public runtime configuration (production). Only public values: never add secrets here.
 * `ng serve` (development configuration) swaps this file for `runtime-config.development.ts`.
 * Note: the repo-wide .gitignore ignores `src/environments/environment*.ts`, hence this name.
 */
export const RUNTIME: { apiBase: string; turnstileSiteKey: string; mockApi: boolean } = {
  /** n8n webhook base. The site calls exactly three endpoints under it: /v6/contact, /v6/news and /v6/plans. */
  apiBase: 'https://n8n.hosting3m.com/webhook',
  /** Public Cloudflare Turnstile sitekey (not a secret). */
  turnstileSiteKey: '0x4AAAAAACaIUH9TvGOgcFq7',
  /** When true no network call is made: the API is simulated locally. */
  mockApi: false,
};
