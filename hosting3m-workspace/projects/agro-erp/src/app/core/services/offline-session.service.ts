import { Injectable, computed, inject, signal } from '@angular/core';
import { Router } from '@angular/router';
import { AuthService, SessionScope, SessionState } from 'core-auth';

/** Route of the PIN unlock screen (outside the main layout). */
export const UNLOCK_ROUTE = '/unlock';

/** Two scopes are the same partition when both user and company match. */
export function isSameScope(a: SessionScope | null, b: SessionScope | null): boolean {
  return !!a && !!b && a.user === b.user && a.id_company === b.id_company;
}

/**
 * Single source of truth for the offline grace UI (#1087, phase 1b-iii-b).
 *
 * - `state` / `scope` / `online` are signals refreshed by `refresh()`, which the watch util calls on
 *   visibility changes, a 60 s timer, navigation, login/logout and tenant switches.
 * - `unlocked` is held in memory only: a cold start in grace asks for the PIN again. It is bound to the
 *   scope it was granted for, so a tenant switch (or any scope change) re-locks.
 * - Reads go through `AuthService.getSessionState()` / `getSessionScope()`, which are side-effect free.
 *   This service never makes HTTP calls and never calls `getStoredToken()` (that one logs out).
 * - Entering grace while the app is open redirects to the unlock screen, unless the user is already on
 *   `/unlock` or `/login`. Cold starts are redirected by the route guards instead.
 */
@Injectable({ providedIn: 'root' })
export class OfflineSessionService {
  private readonly auth = inject(AuthService);
  private readonly router = inject(Router);

  private unlockedFor: SessionScope | null = null;

  private readonly _state = signal<SessionState>('expired');
  private readonly _scope = signal<SessionScope | null>(null);
  private readonly _unlocked = signal(false);
  private readonly _online = signal<boolean>(typeof navigator === 'undefined' || navigator.onLine !== false);

  readonly state = this._state.asReadonly();
  readonly scope = this._scope.asReadonly();
  readonly online = this._online.asReadonly();
  readonly unlocked = this._unlocked.asReadonly();
  /** Grace and not unlocked for this scope: the PIN screen must be shown. */
  readonly locked = computed(() => this._state() === 'grace' && !this._unlocked());

  constructor() {
    // Initial sync without redirect: cold-start redirects belong to the route guards.
    this.sync();
  }

  /** Side-effect-free state read. Any failure counts as `'expired'` (fail-closed). */
  readState(): SessionState {
    try {
      return this.auth.getSessionState();
    } catch {
      return 'expired';
    }
  }

  readScope(): SessionScope | null {
    try {
      return this.auth.getSessionScope();
    } catch {
      return null;
    }
  }

  /** True only in grace, for the current scope, after a successful PIN unlock in this page session. */
  isUnlockedForCurrentScope(): boolean {
    return this.readState() === 'grace' && isSameScope(this.readScope(), this.unlockedFor);
  }

  /** Marks the current grace scope as unlocked. Refused (returns `false`) outside grace or without scope. */
  unlock(): boolean {
    const scope = this.readScope();
    if (!scope || this.readState() !== 'grace') return false;
    this.unlockedFor = { user: scope.user, id_company: scope.id_company };
    this.refresh();
    return true;
  }

  setOnline(online: boolean): void {
    this._online.set(online);
  }

  /** Re-reads the session and, on a transition into a locked grace state, sends the user to unlock. */
  refresh(): void {
    const wasLocked = this.locked();
    this.sync();
    if (!wasLocked && this.locked() && !this.isOnPublicRoute()) {
      void this.router.navigateByUrl(UNLOCK_ROUTE);
    }
  }

  private sync(): void {
    const state = this.readState();
    const scope = this.readScope();
    // Unlock only survives while the state is still grace and the scope is still the same.
    if (state !== 'grace' || !isSameScope(scope, this.unlockedFor)) this.unlockedFor = null;
    this._state.set(state);
    this._scope.set(scope);
    this._unlocked.set(this.unlockedFor !== null);
  }

  private isOnPublicRoute(): boolean {
    const url = this.router.url ?? '';
    return url.startsWith(UNLOCK_ROUTE) || url.startsWith('/login');
  }
}
