import { DestroyRef, inject } from '@angular/core';
import { AuthService, TenantService } from 'core-auth';
import { ComplianceService } from '@features/compliance/services/compliance.service';

/**
 * Resets the compliance state on logout and on every active-tenant change (#1109).
 *
 * - `logout`: clears everything and invalidates in-flight requests. No reload (there is no session).
 * - Any active-tenant emission: clears everything synchronously, so nothing from the previous tenant
 *   can paint, then reloads both sources for the new tenant when there is one. A `null` emission
 *   (context cleared) resets only.
 *
 * The reload is driven here, not by the dashboard, so the card and the UPP list recover even when
 * another part of the dashboard load fails. Subscriptions are synchronous on purpose: the reset must
 * run inside the same `setActiveTenant()` call that changed the tenant. Call once from an app initializer.
 */
export function wireComplianceSessionReset(): void {
  const auth = inject(AuthService);
  const tenants = inject(TenantService);
  const compliance = inject(ComplianceService);

  const subscriptions = [
    auth.sessionEvents$.subscribe(event => {
      if (event.type === 'logout') compliance.resetState();
    }),
    tenants.activeTenantChanges$.subscribe(tenantId => {
      compliance.resetState();
      if (!tenantId) return;
      compliance.loadUppStatus();
      compliance.loadPsgStatus();
    }),
  ];
  inject(DestroyRef).onDestroy(() => subscriptions.forEach(subscription => subscription.unsubscribe()));
}
