import { EnvironmentInjector } from '@angular/core';
import { TestBed } from '@angular/core/testing';
import { ActivatedRouteSnapshot, Router, RouterStateSnapshot, UrlTree, provideRouter } from '@angular/router';
import { TenantService } from 'core-auth';
import { describe, expect, it } from 'vitest';
import { palmSalesGuard } from './palm.guards';

const palm = (role: string | null) => ({ industry: 'Agricultura de Precisión', role });
const cattle = (role: string) => ({ industry: 'Ganadería de Precisión', role });

function run(tenant: unknown) {
  TestBed.resetTestingModule();
  TestBed.configureTestingModule({ providers: [provideRouter([]), { provide: TenantService, useValue: { activeTenant: () => tenant } }] });
  return TestBed.inject(EnvironmentInjector).runInContext(() =>
    palmSalesGuard({} as ActivatedRouteSnapshot, {} as RouterStateSnapshot));
}

describe('palmSalesGuard (role of the active company, never the JWT)', () => {
  it('lets the ADMIN of a palm company in', () => {
    expect(run(palm('ADMIN'))).toBe(true);
    expect(run(palm('admin'))).toBe(true);
  });

  it('sends OWNER, EDITOR, CUSTOMER, GUEST and no role to the palm dashboard', () => {
    for (const role of ['OWNER', 'EDITOR', 'CUSTOMER', 'GUEST', '', null]) {
      const result = run(palm(role));
      expect(result instanceof UrlTree, String(role)).toBe(true);
      expect(TestBed.inject(Router).serializeUrl(result as UrlTree), String(role)).toBe('/agricultura/dashboard');
    }
  });

  it('a livestock or unknown company, or no active company, never gets in even as ADMIN', () => {
    for (const tenant of [cattle('ADMIN'), { industry: 'Generic', role: 'ADMIN' }, null, undefined]) {
      expect(run(tenant) instanceof UrlTree).toBe(true);
    }
  });
});
