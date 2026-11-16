import { resolveSessionIdentity } from './session-identity.util';

describe('resolveSessionIdentity', () => {
  it('in grace shows the scope user and the active company role, never the fallbacks', () => {
    const id = resolveSessionIdentity({
      state: 'grace', scopeUser: 'ana@example.com', currentUserName: undefined,
      currentUserRole: undefined, activeTenantRole: 'editor',
    });
    expect(id).toEqual({ initial: 'A', name: 'ana@example.com', role: 'EDITOR' });
    expect(JSON.stringify(id)).not.toMatch(/Administrador|Socio Operativo/);
  });

  it('in grace without a scope shows a dash, not an identity', () => {
    const id = resolveSessionIdentity({
      state: 'grace', scopeUser: null, currentUserName: undefined, currentUserRole: undefined, activeTenantRole: null,
    });
    expect(id).toEqual({ initial: '—', name: '—', role: '—' });
  });

  it('valid keeps the JWT identity and the existing fallbacks', () => {
    expect(resolveSessionIdentity({
      state: 'valid', scopeUser: 'ana', currentUserName: 'Ana', currentUserRole: 'ADMIN', activeTenantRole: 'EDITOR',
    })).toEqual({ initial: 'A', name: 'Ana', role: 'ADMIN' });
    expect(resolveSessionIdentity({
      state: 'valid', scopeUser: null, currentUserName: undefined, currentUserRole: undefined, activeTenantRole: null,
    })).toEqual({ initial: 'U', name: 'Administrador', role: 'Socio Operativo' });
  });
});
