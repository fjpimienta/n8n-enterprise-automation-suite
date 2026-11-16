import type { SessionState } from 'core-auth';

export interface SessionIdentityInput {
  state: SessionState;
  /** Partition user (email or login) from `AuthService.getSessionScope()`. */
  scopeUser: string | null;
  /** JWT identity, only available while the token is valid. */
  currentUserName: string | null | undefined;
  currentUserRole: string | null | undefined;
  /** Role of the active company (per-tenant, kept in localStorage). */
  activeTenantRole: string | null | undefined;
}

export interface SessionIdentity {
  initial: string;
  name: string;
  role: string;
}

/**
 * Identity shown in the header. In `'grace'` the JWT is expired and not loaded, so the label comes
 * from the session scope and the active company, never from the "Administrador" / "Socio Operativo"
 * fallbacks (those would show an admin identity for any user).
 */
export function resolveSessionIdentity(input: SessionIdentityInput): SessionIdentity {
  if (input.state === 'grace') {
    const user = input.scopeUser?.trim() || '—';
    return {
      initial: user === '—' ? '—' : user.charAt(0).toUpperCase(),
      name: user,
      role: input.activeTenantRole?.toUpperCase() || '—',
    };
  }
  return {
    initial: input.currentUserName?.charAt(0) || 'U',
    name: input.currentUserName || 'Administrador',
    role: input.currentUserRole || 'Socio Operativo',
  };
}
