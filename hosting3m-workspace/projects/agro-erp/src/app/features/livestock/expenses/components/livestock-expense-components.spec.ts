import { TestBed } from '@angular/core/testing';
import { describe, expect, it } from 'vitest';
import { todayCdmx } from '../../../agriculture/utils/agri.util';
import type { Expense } from '../../models/expense.model';
import type { Livestock } from '../../models/livestock.model';
import { unweightedHeads } from '@shared/utils/herd-status.util';
import { LivestockAnimalCostsComponent } from './livestock-animal-costs/livestock-animal-costs.component';
import { LivestockExpenseHistoryComponent } from './livestock-expense-history/livestock-expense-history.component';
import { LivestockExpenseSummaryComponent } from './livestock-expense-summary/livestock-expense-summary.component';

const TODAY = todayCdmx();
const cow = (o: Partial<Livestock> = {}): Livestock => ({
  id: 'a1', business_model: 'CRIA', category: 'VACA', current_weight_kg: 100, rfid_siniiga: '0700000001', numero_fuego: 'F1',
  production_unit_id: 'u1', upp_code: 'UPP-1', ...o });
const exp = (o: Partial<Expense> = {}): Expense => ({ id: 'e' + Math.random(), expense_date: TODAY, category: 'ALIMENTACION', amount: 1250, ...o });

function render<T>(type: new () => T, inputs: Record<string, unknown>) {
  const fixture = TestBed.createComponent(type);
  for (const [k, v] of Object.entries(inputs)) fixture.componentRef.setInput(k, v);
  fixture.detectChanges();
  const el = fixture.nativeElement as HTMLElement;
  return { fixture, el, text: () => (el.textContent ?? '').replace(/\s+/g, ' ') };
}
const press = (el: HTMLElement, label: string) =>
  (Array.from(el.querySelectorAll('button')).find(b => b.textContent?.trim().startsWith(label)) as HTMLButtonElement).click();

describe('app-livestock-expense-summary', () => {
  const cattle = [cow(), cow({ id: 'a2', production_unit_id: null, upp_code: null, current_weight_kg: 50 })];
  const expenses = [exp({ livestock_id: 'a1', amount: 1000 }), exp({ amount: 250, category: 'HERRAJES' })];
  const inputs = { canViewAmounts: true, cattle, expenses, pricePerKg: 10, resetKey: 'k1' };

  it('renders the KPIs, the reference price, the no-UPP alert and the balance table with the general row', () => {
    const { text } = render(LivestockExpenseSummaryComponent, inputs);
    expect(text()).toContain('Gasto del periodo');
    expect(text()).toContain('$1,250.00');
    expect(text()).toContain('Valor estimado del hato');
    expect(text()).toContain('$1,500.00');
    expect(text()).toContain('Precio de referencia $10.00/kg');
    expect(text()).toContain('1 de 2 animales (50%) sin UPP asignada');
    expect(text()).toContain('Acumulado');
    expect(text()).toContain('UPP-1');
    expect(text()).toContain('Gastos generales');
    expect(text()).toContain('Gasto por cabeza');
    expect(text()).toContain('$625.00'); // 1250 / 2 heads
  });

  it('shows other categories as received in the spend by type', () => {
    const { text } = render(LivestockExpenseSummaryComponent, inputs);
    expect(text()).toContain('Herrajes');
    expect(text()).toContain('Alimentación');
  });

  it('resets the period when the reset key changes', () => {
    const { fixture, el } = render(LivestockExpenseSummaryComponent, inputs);
    const pressed = () => Array.from(el.querySelectorAll('exp-period-chips button')).map(b => b.getAttribute('aria-pressed'));
    expect(pressed()).toEqual(['true', 'false', 'false']);
    press(el, 'Año');
    fixture.detectChanges();
    expect(pressed()).toEqual(['false', 'false', 'true']);
    fixture.componentRef.setInput('resetKey', 'k2');
    fixture.detectChanges();
    fixture.detectChanges();
    expect(pressed()).toEqual(['true', 'false', 'false']);
  });

  it('renders nothing (no amounts) when the admin flag is false', () => {
    const { el, text } = render(LivestockExpenseSummaryComponent, { ...inputs, canViewAmounts: false });
    expect(el.querySelector('.exp-screen')).toBeNull();
    expect(text()).not.toContain('$');
    expect(text().trim()).toBe('');
  });

  it('shows a loading state while there is no data yet', () => {
    const { text } = render(LivestockExpenseSummaryComponent, { canViewAmounts: true, loading: true });
    expect(text()).toContain('Cargando');
  });
});

describe('app-livestock-expense-summary: animals without weight', () => {
  const base = { canViewAmounts: true, expenses: [], pricePerKg: 10, resetKey: 'k1' };
  const noWeight = (o: Partial<Livestock> = {}) => cow({ current_weight_kg: undefined, ...o });

  it('shows nothing new when every valued animal has a weight', () => {
    const { text } = render(LivestockExpenseSummaryComponent, { ...base, cattle: [cow(), cow({ id: 'a2' })] });
    expect(text()).not.toContain('sin peso');
    expect(text()).not.toContain('0 animales');
  });

  it('uses the singular for one animal and the plural otherwise', () => {
    const one = render(LivestockExpenseSummaryComponent, { ...base, cattle: [cow(), noWeight({ id: 'a2' })] });
    expect(one.text()).toContain('1 animal sin peso no suma al valor');
    const two = render(LivestockExpenseSummaryComponent, { ...base, cattle: [noWeight(), noWeight({ id: 'a2', current_weight_kg: '0' as unknown as number })] });
    expect(two.text()).toContain('2 animales sin peso no suman al valor');
  });

  it('does not count deceased animals', () => {
    const { text } = render(LivestockExpenseSummaryComponent, { ...base, cattle: [cow(), noWeight({ id: 'a2', current_status: 'BAJA_MORTANDAD' })] });
    expect(text()).not.toContain('sin peso no suma');
  });

  it('says in the no-UPP warning that all of them add $0 when none has a weight', () => {
    const cattle = [noWeight({ production_unit_id: null, upp_code: null }), noWeight({ id: 'a2', production_unit_id: null, upp_code: null })];
    const { text } = render(LivestockExpenseSummaryComponent, { ...base, cattle });
    expect(text()).toContain('2 de 2 animales (100%) sin UPP asignada');
    expect(text()).toContain('Ninguno tiene peso registrado, por eso suman $0.00.');
  });

  it('says how many of the no-UPP animals lack weight when only some do', () => {
    const cattle = [
      noWeight({ production_unit_id: null, upp_code: null }),
      cow({ id: 'a2', production_unit_id: null, upp_code: null, current_weight_kg: 50 }),
      cow({ id: 'a3' }),
    ];
    const { text } = render(LivestockExpenseSummaryComponent, { ...base, cattle });
    expect(text()).toContain('2 de 3 animales (66.7%) sin UPP asignada');
    expect(text()).toContain('1 de ellos no tiene peso registrado y suma $0.00.');
  });

  it('adds no weight text to the warning when the no-UPP animals all have a weight', () => {
    const cattle = [cow({ production_unit_id: null, upp_code: null })];
    const { text } = render(LivestockExpenseSummaryComponent, { ...base, cattle });
    expect(text()).toContain('sin UPP asignada');
    expect(text()).not.toContain('peso registrado');
  });

  it('agrees with the no-UPP warning on a mixed fixture (production unit set but empty code counts as no UPP)', () => {
    const cattle = [
      noWeight({ production_unit_id: null, upp_code: null }),
      noWeight({ id: 'a2', production_unit_id: 'u1', upp_code: '' }),
      noWeight({ id: 'a3', production_unit_id: 'u1', upp_code: 'UPP-1' }),
      cow({ id: 'a4', production_unit_id: 'u1', upp_code: ' ' }),
      cow({ id: 'a5' }),
    ];
    const { text } = render(LivestockExpenseSummaryComponent, { ...base, cattle });
    expect(text()).toContain('3 de 5 animales (60%) sin UPP asignada');
    expect(unweightedHeads(cattle).withoutWeightAndUpp).toBe(2);
    expect(text()).toContain('2 de ellos no tienen peso registrado y suman $0.00.');
  });

  it('shows none of it to a non-ADMIN', () => {
    const { text } = render(LivestockExpenseSummaryComponent, { ...base, canViewAmounts: false, cattle: [noWeight()] });
    expect(text()).not.toContain('sin peso');
    expect(text().trim()).toBe('');
  });
});

describe('app-livestock-expense-summary: Resultado del periodo', () => {
  const sale = (o: Record<string, unknown> = {}) => ({
    id: 's' + Math.random(), tenantId: 3, livestockId: 'a1', pendingAuthorizationId: null, saleDate: TODAY, saleMode: 'PER_HEAD', amount: 5000,
    weightKg: null, pricePerKg: null, buyerName: 'Rancho Norte', paymentMethod: 'EFECTIVO', invoiced: false, invoiceFolio: null, banked: false, guiaTransito: null, ...o });
  const base = {
    canViewAmounts: true, cattle: [cow()], expenses: [exp({ amount: 1500 })], pricePerKg: 10, resetKey: 'k1', lookup: [cow()],
    incomes: [sale()], incomesLoaded: true,
    mortalityCattle: [cow({ id: 'd1', current_weight_kg: 200 }), cow({ id: 'd2', current_weight_kg: 0 })],
  };

  it('renders income, the signed result, sold heads, mortality and the sales list', () => {
    const { text } = render(LivestockExpenseSummaryComponent, base);
    expect(text()).toContain('Resultado del periodo');
    expect(text()).toContain('Ingresos por ventas');
    expect(text()).toContain('$5,000.00');
    expect(text()).toContain('+$3,500.00');
    expect(text()).toContain('Ganancia');
    expect(text()).toContain('Cabezas vendidas');
    expect(text()).toContain('Rancho Norte');
    expect(text()).toContain('Pérdida estimada');
    expect(text()).toContain('$2,000.00');
    expect(text()).toContain('1 sin peso');
    expect(text()).toContain('Acumulado');
    expect(text()).toContain('Resultado acumulado');
  });

  it('shows a negative result with its sign and word', () => {
    const { text } = render(LivestockExpenseSummaryComponent, { ...base, incomes: [] });
    expect(text()).toContain('−$1,500.00');
    expect(text()).toContain('Pérdida');
    expect(text()).toContain('Sin ventas en el periodo');
  });

  it('opens the Ingresos tab from the link', () => {
    const { fixture, el } = render(LivestockExpenseSummaryComponent, base);
    let opened = 0;
    fixture.componentInstance.openSales.subscribe(() => opened++);
    press(el, 'Ver ingresos');
    expect(opened).toBe(1);
  });

  it('never turns a failed load into zeros: explicit error before the first load', () => {
    const { text } = render(LivestockExpenseSummaryComponent, { ...base, incomes: [], incomesLoaded: false, incomesError: 'Sin conexión' });
    expect(text()).toContain('No se pudieron cargar los ingresos por venta');
    expect(text()).not.toContain('Cabezas vendidas');
  });

  it('keeps the last data and warns when a later refresh fails', () => {
    const { text } = render(LivestockExpenseSummaryComponent, { ...base, incomesError: 'Sin conexión' });
    expect(text()).toContain('Se conserva la última información disponible');
    expect(text()).toContain('Rancho Norte');
  });

  it('renders no incomes or amounts when the admin flag is false', () => {
    const { text } = render(LivestockExpenseSummaryComponent, { ...base, canViewAmounts: false });
    expect(text()).not.toContain('Rancho Norte');
    expect(text()).not.toContain('$');
  });
});

describe('app-livestock-expense-history', () => {
  const cattle = [cow()];
  const expenses = [
    exp({ id: '1', description: 'Pastura del lote', livestock_id: 'a1', amount: 800 }),
    exp({ id: '2', description: 'Flete de ganado', category: 'MANEJO', amount: 450 }),
  ];
  const inputs = { canViewAmounts: true, expenses, cattle, lookup: cattle, resetKey: 'k1' };

  it('lists the expenses and filters by search', () => {
    const { fixture, el, text } = render(LivestockExpenseHistoryComponent, inputs);
    expect(text()).toContain('Pastura del lote');
    expect(text()).toContain('Flete de ganado');
    fixture.componentInstance.search.set('flete');
    fixture.detectChanges();
    expect(el.querySelector('.exp-desktop')!.textContent).not.toContain('Pastura del lote');
    expect(el.querySelector('.exp-desktop')!.textContent).toContain('Flete de ganado');
  });

  it('"Solo gastos generales" keeps the expenses without animal', () => {
    const { fixture, el } = render(LivestockExpenseHistoryComponent, inputs);
    press(el, 'Solo gastos generales');
    fixture.detectChanges();
    const body = el.querySelector('.exp-desktop')!.textContent!;
    expect(body).toContain('Flete de ganado');
    expect(body).not.toContain('Pastura del lote');
  });

  it('opens the detail panel from a real button and closes it', () => {
    const { fixture, el, text } = render(LivestockExpenseHistoryComponent, inputs);
    (el.querySelector('.exp-desktop .exp-row-btn') as HTMLButtonElement).click();
    fixture.detectChanges();
    expect(el.querySelector('exp-detail-panel')).not.toBeNull();
    expect(text()).toContain('Detalle del gasto');
    (el.querySelector('button[aria-label="Cerrar detalle"]') as HTMLButtonElement).click();
    fixture.detectChanges();
    expect(el.querySelector('exp-detail-panel')).toBeNull();
  });

  it('resets filters and selection when the reset key changes', () => {
    const { fixture, el } = render(LivestockExpenseHistoryComponent, inputs);
    fixture.componentInstance.search.set('flete');
    (el.querySelector('.exp-desktop .exp-row-btn') as HTMLButtonElement | null)?.click();
    fixture.detectChanges();
    fixture.componentRef.setInput('resetKey', 'k2');
    fixture.detectChanges();
    fixture.detectChanges();
    expect(fixture.componentInstance.search()).toBe('');
    expect(fixture.componentInstance.selectedId()).toBeNull();
  });

  it('renders nothing when the admin flag is false', () => {
    const { text } = render(LivestockExpenseHistoryComponent, { ...inputs, canViewAmounts: false });
    expect(text()).not.toContain('$');
    expect(text()).not.toContain('Pastura');
  });
});

describe('app-livestock-animal-costs', () => {
  const lookup = [cow({ id: 'a1', current_weight_kg: 100 }), cow({ id: 'a2', rfid_siniiga: '0700000002', current_weight_kg: 0 }), cow({ id: 'a3', rfid_siniiga: '0700000003', current_weight_kg: 100 })];
  const expenses = [exp({ livestock_id: 'a1', amount: 960 }), exp({ livestock_id: 'a2', amount: 300 }), exp({ livestock_id: 'a3', amount: 100 })];
  const inputs = { canViewAmounts: true, expenses, lookup, pricePerKg: 10, resetKey: 'k1' };

  it('renders the cost table with the risk rule, "Sin peso" and dashes', () => {
    const { text } = render(LivestockAnimalCostsComponent, inputs);
    expect(text()).toContain('0700000001');
    expect(text()).toContain('⚠ En riesgo');
    expect(text()).toContain('Sin peso');
    expect(text()).toContain('menor al 10% del valor estimado');
    expect(text()).toContain('Solo en riesgo (1)');
    expect(text()).toContain('Acumulado');
  });

  it('"Solo en riesgo" shows only the flagged animals', () => {
    const { fixture, el } = render(LivestockAnimalCostsComponent, inputs);
    press(el, 'Solo en riesgo');
    fixture.detectChanges();
    const body = el.querySelector('.exp-desktop tbody')!.textContent!;
    expect(body).toContain('0700000001');
    expect(body).not.toContain('0700000002');
    expect(body).not.toContain('0700000003');
  });

  it('sorts by worst balance (no weight last) and resets on key change', () => {
    const { fixture, el } = render(LivestockAnimalCostsComponent, inputs);
    press(el, 'Peor balance');
    fixture.detectChanges();
    const first = () => el.querySelector('.exp-desktop tbody tr td strong')!.textContent;
    expect(first()).toBe('0700000001');
    fixture.componentRef.setInput('resetKey', 'k2');
    fixture.detectChanges();
    fixture.detectChanges();
    expect(fixture.componentInstance.sort()).toBe('SPEND');
    expect(fixture.componentInstance.onlyRisk()).toBe(false);
  });

  it('renders nothing when the admin flag is false', () => {
    const { text } = render(LivestockAnimalCostsComponent, { ...inputs, canViewAmounts: false });
    expect(text().trim()).toBe('');
  });
});
