/**
 * Local development configuration (`ng serve dashboard`, the default serve configuration).
 * Placeholder endpoints only: they point at this machine and can never reach a production host.
 * To run against a local n8n, edit the ports/paths below in YOUR checkout only; do not commit real hosts.
 * The production and CI environment file (`environment.ts`, generated and git-ignored) is not used by this configuration.
 */
export const environment = {
  production: false,
  apiUrl: 'http://localhost:5678',
  apiUrl_ai: 'http://localhost:5678/webhook/ai/chat',
  apiUrl_crud: 'http://localhost:5678/webhook/crud',
  apiUrl_token: 'http://localhost:5678/webhook/token',
  apiUrl_upload: 'http://localhost:5678/upload',
  system_id: 'dashboard'
};
