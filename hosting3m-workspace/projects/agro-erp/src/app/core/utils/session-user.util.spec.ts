import { HttpRequest } from '@angular/common/http';
import { isLoginRequest, userFromStoredToken } from './session-user.util';

function b64url(obj: unknown): string {
  return btoa(JSON.stringify(obj)).replace(/=+$/, '').replace(/\+/g, '-').replace(/\//g, '_');
}
const jwt = (claims: Record<string, unknown>) => `${b64url({ alg: 'HS256', typ: 'JWT' })}.${b64url(claims)}.sig`;
const TOKEN = 'https://api.example.test/token';

describe('userFromStoredToken', () => {
  function storageWith(value: string | null): Storage {
    return { getItem: () => value } as unknown as Storage;
  }

  it('reads the user claim, falling back to email', () => {
    expect(userFromStoredToken(storageWith(jwt({ user: 'ana', email: 'x@y.z' })))).toBe('ana');
    expect(userFromStoredToken(storageWith(jwt({ email: 'beto@example.com' })))).toBe('beto@example.com');
  });

  it('trims the value', () => {
    expect(userFromStoredToken(storageWith(jwt({ user: '  ana  ' })))).toBe('ana');
  });

  it('returns null without a token, with a malformed one, or without identity claims', () => {
    expect(userFromStoredToken(storageWith(null))).toBeNull();
    expect(userFromStoredToken(storageWith('not-a-jwt'))).toBeNull();
    expect(userFromStoredToken(storageWith(jwt({ role: 'ADMIN' })))).toBeNull();
    expect(userFromStoredToken(storageWith(jwt({ user: '   ' })))).toBeNull();
  });
});

describe('isLoginRequest', () => {
  const config = { apiUrl_token: TOKEN };
  const req = (method: string, url: string) => new HttpRequest(method, url, null);

  it('matches the POST to the token endpoint, ignoring a trailing slash', () => {
    expect(isLoginRequest(req('POST', TOKEN), config)).toBe(true);
    expect(isLoginRequest(req('POST', `${TOKEN}/`), config)).toBe(true);
  });

  it('does not match other methods, paths or origins', () => {
    expect(isLoginRequest(req('GET', TOKEN), config)).toBe(false);
    expect(isLoginRequest(req('POST', 'https://api.example.test/crud/v6/companys'), config)).toBe(false);
    expect(isLoginRequest(req('POST', 'https://evil.example.test/token'), config)).toBe(false);
    expect(isLoginRequest(req('POST', TOKEN), { apiUrl_token: '' })).toBe(false);
  });
});
