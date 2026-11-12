import { computed, signal } from '@angular/core';
import { ComponentFixture, TestBed } from '@angular/core/testing';
import { beforeEach, describe, expect, it } from 'vitest';
import { TenantService } from 'core-auth';
import { CattleApiService } from '@core/services/cattle-api.service';
import { CattleDataService } from '@core/services/cattle-data.service';
import { CattleListComponent } from './cattle-list.component';

describe('CattleListComponent — "Nuevo Registro" entry point', () => {
  let fixture: ComponentFixture<CattleListComponent>;
  const role = signal<string>('ADMIN');
  const tenant = signal<string>('3');

  function create() {
    fixture = TestBed.createComponent(CattleListComponent);
    fixture.detectChanges();
    return fixture.componentInstance;
  }
  const button = () => fixture.nativeElement.querySelector('[data-testid="new-record"]') as HTMLElement | null;

  beforeEach(() => {
    role.set('ADMIN');
    tenant.set('3');
    TestBed.configureTestingModule({
      providers: [
        {
          provide: CattleDataService,
          useValue: { cattleList: signal([]), isLoading: signal(false), loadCattleData: () => Promise.resolve() }
        },
        { provide: CattleApiService, useValue: { getCattleLotHistory: () => Promise.resolve([]) } },
        { provide: TenantService, useValue: { activeTenant: computed(() => ({ role: role(), company_name: 'Demo' })), activeTenantId: computed(() => tenant()) } }
      ]
    });
  });

  it.each(['ADMIN', 'EDITOR'])('tenant 3: %s sees the entry point', r => {
    role.set(r);
    create();
    expect(button()).not.toBeNull();
  });

  it.each(['OWNER', 'CUSTOMER'])('tenant 3: %s does not see the entry point and cannot open it', r => {
    role.set(r);
    const c = create();
    expect(button()).toBeNull();
    c.openModal('ALTA');
    expect(c.isModalOpen).toBe(false);
  });

  it.each(['ADMIN', 'EDITOR', 'OWNER', 'CUSTOMER'])('tenant 5 (legacy): %s still sees the entry point', r => {
    tenant.set('5');
    role.set(r);
    const c = create();
    expect(button()).not.toBeNull();
    c.openModal('ALTA');
    expect(c.isModalOpen).toBe(true);
  });

  it('follows an active-tenant change in the same session', () => {
    role.set('OWNER');
    tenant.set('5');
    const c = create();
    expect(c.canRegisterAnimal()).toBe(true);
    tenant.set('3');
    expect(c.canRegisterAnimal()).toBe(false);
    tenant.set('5');
    expect(c.canRegisterAnimal()).toBe(true);
  });

  it('shows the success notice after a saved panel ALTA (tenant 3)', () => {
    const c = create();
    c.openModal('ALTA');
    c.onModalClose(true);
    fixture.detectChanges();
    expect(fixture.nativeElement.querySelector('[data-testid="registered-notice"]')?.textContent).toContain('Animal registrado.');
  });

  it('shows no notice after a saved legacy ALTA (tenant 5)', () => {
    tenant.set('5');
    const c = create();
    c.openModal('ALTA');
    c.onModalClose(true);
    fixture.detectChanges();
    expect(fixture.nativeElement.querySelector('[data-testid="registered-notice"]')).toBeNull();
  });
});
