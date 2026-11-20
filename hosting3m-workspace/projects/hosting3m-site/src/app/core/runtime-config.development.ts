/** Local development: simulate the API (CORS only allows the production and beta origins). */
export const RUNTIME: { apiBase: string; turnstileSiteKey: string; mockApi: boolean } = {
  apiBase: 'https://n8n.hosting3m.com/webhook',
  turnstileSiteKey: '0x4AAAAAACaIUH9TvGOgcFq7',
  mockApi: true,
};
