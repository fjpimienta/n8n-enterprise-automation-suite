import { signal } from '@angular/core';
import { TestBed } from '@angular/core/testing';
import { TenantService } from 'core-auth';
import { describe, expect, it } from 'vitest';
import type { ExpenseBalance } from '@core/models/agri-expense.model';
import { AgriApiService } from '../services/agri-api.service';
import { PlantationContextService } from '../services/plantation-context.service';
import { ExpenseBalanceComponent } from './expense-balance.component';
import { ExpenseListComponent } from './expense-list.component';

const balance = (total: number): ExpenseBalance => ({
  grain: 'DAY', dateFrom: '2026-11-01', dateTo: '2026-11-30', totalAmount: total, expenseCount: total ? 1 : 0, generalAmount: 0,
  byPeriod: [{ periodStart: '2026-11-01', periodEnd: '2026-11-01', totalAmount: total, expenseCount: total ? 1 : 0 }], byCategory: [], byPlantation: [], byLot: [],
});

function setup(total = 0) {
  TestBed.configureTestingModule({
    providers: [
      { provide: TenantService, useValue: { activeTenantId: signal('10'), activeTenant: signal({ role: 'ADMIN' }) } },
      { provide: PlantationContextService, useValue: { allPlantations: signal([]), availablePlantations: signal([]), activePlantationId: signal(null) } },
      {
        provide: AgriApiService,
        useValue: {
          getExpenseBalance: async () => balance(total),
          getExpenses: async () => ({ items: [], possiblyTruncated: false }),
          getExpenseSummary: async () => ({ items: [], possiblyTruncated: false }),
          getLots: async () => ({ items: [] }),
        },
      },
    ],
  });
}

describe('agriculture expense screens use the shared themed host, whatever the browser theme', () => {
  it('Balance renders inside .exp-screen (not livestock) so the dark palette applies to it', async () => {
    setup();
    const fixture = TestBed.createComponent(ExpenseBalanceComponent);
    fixture.detectChanges();
    await fixture.whenStable();
    fixture.detectChanges();
    const root = (fixture.nativeElement as HTMLElement).querySelector('.exp-screen');
    expect(root).not.toBeNull();
    expect(root!.classList.contains('exp-livestock')).toBe(false);
  });

  it('Gastos registrados renders inside .exp-screen', async () => {
    setup();
    const fixture = TestBed.createComponent(ExpenseListComponent);
    fixture.detectChanges();
    await fixture.whenStable();
    expect((fixture.nativeElement as HTMLElement).querySelector('.exp-screen')).not.toBeNull();
  });

  it('shows "Sin gastos en el periodo" instead of a blank day chart when every day is $0', async () => {
    setup(0);
    const fixture = TestBed.createComponent(ExpenseBalanceComponent);
    fixture.detectChanges();
    await fixture.whenStable();
    fixture.detectChanges();
    const el = fixture.nativeElement as HTMLElement;
    expect(el.querySelector('exp-trend-bars')!.textContent).toContain('Sin gastos en el periodo');
    expect(el.querySelector('exp-trend-bars .exp-labels')).toBeNull();
  });
});
