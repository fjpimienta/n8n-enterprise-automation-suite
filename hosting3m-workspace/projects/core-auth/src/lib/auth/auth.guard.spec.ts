import { TestBed } from '@angular/core/testing';
import { CanActivateFn } from '@angular/router';

import { authGuard, roleGuard } from './auth.guard';

describe('authGuard', () => {
    const executeGuard: CanActivateFn = (...guardParameters) =>
        TestBed.runInInjectionContext(() => authGuard(...guardParameters));

    beforeEach(() => {
        TestBed.configureTestingModule({});
    });

    it('should be created', () => {
        expect(executeGuard).toBeTruthy();
    });
});

describe('roleGuard', () => {
    const executeRoleGuard = (roles: string[]): CanActivateFn => {
        return (...guardParameters) =>
            TestBed.runInInjectionContext(() => roleGuard(roles)(...guardParameters));
    };

    beforeEach(() => {
        TestBed.configureTestingModule({});
    });

    it('should be created', () => {
        const guard = executeRoleGuard(['ADMIN']);
        expect(guard).toBeTruthy();
    });
});