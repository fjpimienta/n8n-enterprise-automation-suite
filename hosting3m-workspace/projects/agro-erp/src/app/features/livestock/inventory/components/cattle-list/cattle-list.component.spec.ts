import { signal } from '@angular/core';
import { ComponentFixture, TestBed } from '@angular/core/testing';
import { beforeEach, describe, expect, it } from 'vitest';
import { TenantService } from 'core-auth';
import { CattleApiService } from '@core/services/cattle-api.service';
import { CattleDataService } from '@core/services/cattle-data.service';
import { CattleListComponent } from './cattle-list.component';

describe('CattleListComponent — "Nuevo Registro" entry point', () => {
  let fixture: ComponentFixture<CattleListComponent>;
  const role = signal<string>('ADMIN');

  function create(panelAltaEnabled: boolean) {
    fixture = TestBed.createComponent(CattleListComponent);
    fixture.componentInstance.panelAltaEnabled = panelAltaEnabled;
    fixture.detectChanges();
    return fixture.componentInstance;
  }
  const button = () => fixture.nativeElement.querySelector('[data-testid="new-record"]') as HTMLElement | null;

  beforeEach(() => {
    role.set('ADMIN');
    TestBed.configureTestingModule({
      providers: [
        {
          provide: CattleDataService,
          useValue: { cattleList: signal([]), isLoading: signal(false), loadCattleData: () => Promise.resolve() }
        },
        { provide: CattleApiService, useValue: { getCattleLotHistory: () => Promise.resolve([]) } },
        { provide: TenantService, useValue: { activeTenant: () => ({ role: role(), company_name: 'Demo' }), activeTenantId: () => '3' } }
      ]
    });
  });

  it.each(['ADMIN', 'EDITOR'])('switch ON: %s sees the entry point', r => {
    role.set(r);
    create(true);
    expect(button()).not.toBeNull();
  });

  it.each(['OWNER', 'CUSTOMER'])('switch ON: %s does not see the entry point and cannot open it', r => {
    role.set(r);
    const c = create(true);
    expect(button()).toBeNull();
    c.openModal('ALTA');
    expect(c.isModalOpen).toBe(false);
  });

  it('switch OFF: the entry point is unchanged for every role (OWNER included)', () => {
    role.set('OWNER');
    const c = create(false);
    expect(button()).not.toBeNull();
    c.openModal('ALTA');
    expect(c.isModalOpen).toBe(true);
  });

  it('shows the success notice after a saved panel ALTA', () => {
    const c = create(true);
    c.openModal('ALTA');
    c.onModalClose(true);
    fixture.detectChanges();
    expect(fixture.nativeElement.querySelector('[data-testid="registered-notice"]')?.textContent).toContain('Animal registrado.');
  });
});
