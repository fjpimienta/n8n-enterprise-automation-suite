import { TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { describe, expect, it } from 'vitest';
import { RoomCardCompactComponent } from './room-card-compact.component';
import { RoomFilterBarComponent } from './room-filter-bar.component';
import { KpiCardComponent } from './kpi-card.component';
import { TodayPanelComponent } from './today-panel.component';
import { MaintenancePanelComponent } from './maintenance-panel.component';
import { NextSidebarComponent } from './next-sidebar.component';
import { BottomNavComponent } from './bottom-nav.component';
import { buildNav } from '../logic/nav';
import { RoomView, toRoomViews } from '../logic/room-view';

function render<T>(type: new () => T, inputs: Record<string, unknown>, providers: unknown[] = []) {
  TestBed.configureTestingModule({ imports: [type], providers: providers as never[] });
  const fixture = TestBed.createComponent(type);
  for (const [k, v] of Object.entries(inputs)) fixture.componentRef.setInput(k, v);
  fixture.detectChanges();
  return fixture;
}

const room = (o: Record<string, unknown>): RoomView =>
  toRoomViews([{ id: 1, room_number: '101', type: 'DOBLE', status: 'available', cleaning_status: 'clean', hasPendingTicket: false, ...o }])[0];

describe('RoomCardCompactComponent', () => {
  it('shows number, Spanish chip, accessible name and Spanish date line', () => {
    const f = render(RoomCardCompactComponent, { room: room({ status: 'occupied', displayDate: '2026-12-18T00:00:00.000Z', description: '2 camas' }) });
    const el: HTMLElement = f.nativeElement;
    expect(el.querySelector('.h-room__number')?.textContent).toBe('101');
    expect(el.querySelector('.h-chip')?.textContent?.trim()).toBe('Ocupada');
    expect(el.querySelector('.h-room')?.getAttribute('aria-label')).toBe('Habitación 101, Ocupada');
    expect(el.textContent).toContain('Sale 18 dic');
    expect(el.textContent).not.toMatch(/AVAILABLE|OCCUPIED|PAID/);
  });

  it('flags a reported failure without hiding the main status', () => {
    const f = render(RoomCardCompactComponent, { room: room({ hasPendingTicket: true }) });
    expect(f.nativeElement.textContent).toContain('Falla reportada');
    expect(f.nativeElement.textContent).toContain('Disponible');
  });

  it('keeps leading zeros and emits the room id for select and report', () => {
    const f = render(RoomCardCompactComponent, { room: room({ id: 7, room_number: '007' }) });
    const c = f.componentInstance;
    const selected: number[] = []; const reported: number[] = [];
    c.select.subscribe(v => selected.push(v)); c.report.subscribe(v => reported.push(v));
    const el: HTMLElement = f.nativeElement;
    expect(el.querySelector('.h-room__number')?.textContent).toBe('007');
    (el.querySelector('.h-room') as HTMLButtonElement).click();
    (el.querySelector('.h-room__report') as HTMLButtonElement).click();
    expect(selected).toEqual([7]);
    expect(reported).toEqual([7]);
    expect(el.querySelector('.h-room__report')?.getAttribute('aria-label')).toContain('007');
  });

  it('hides the report button for rooms already in maintenance', () => {
    const f = render(RoomCardCompactComponent, { room: room({ status: 'maintenance' }) });
    expect(f.nativeElement.querySelector('.h-room__report')).toBeNull();
  });
});

describe('RoomFilterBarComponent', () => {
  const options = [{ value: 'all', label: 'Todas', count: 18 }, { value: 'occupied', label: 'Ocupadas', count: null }];
  it('renders counts, shows "—" for unknown and marks the active filter', () => {
    const f = render(RoomFilterBarComponent, { options, active: 'all', query: '' });
    const buttons = Array.from(f.nativeElement.querySelectorAll('.h-filter')) as HTMLButtonElement[];
    expect(buttons[0].textContent).toContain('18');
    expect(buttons[1].textContent).toContain('—');
    expect(buttons[0].getAttribute('aria-pressed')).toBe('true');
    expect(buttons[1].getAttribute('aria-pressed')).toBe('false');
  });
  it('emits filter and query changes', () => {
    const f = render(RoomFilterBarComponent, { options, active: 'all', query: '' });
    const seen: string[] = [];
    f.componentInstance.filterChange.subscribe(v => seen.push(v));
    f.componentInstance.queryChange.subscribe(v => seen.push('q:' + v));
    (f.nativeElement.querySelectorAll('.h-filter')[1] as HTMLButtonElement).click();
    const input = f.nativeElement.querySelector('input') as HTMLInputElement;
    input.value = '30'; input.dispatchEvent(new Event('input'));
    expect(seen).toEqual(['occupied', 'q:30']);
    expect(f.nativeElement.querySelector('label[for="h-room-search"]')).not.toBeNull();
  });
});

describe('KpiCardComponent', () => {
  it('shows unknown as a dash and exposes an accessible name', () => {
    const f = render(KpiCardComponent, { label: 'Llegadas hoy', value: '—', icon: 'login', hint: '' });
    expect(f.nativeElement.querySelector('.h-kpi__value')?.textContent?.trim()).toBe('—');
    expect(f.nativeElement.querySelector('[role=group]')?.getAttribute('aria-label')).toBe('Llegadas hoy: —');
  });
});

describe('TodayPanelComponent and MaintenancePanelComponent', () => {
  it('distinguishes unknown from an empty day', () => {
    expect(render(TodayPanelComponent, { title: 'Llegadas', icon: 'login', items: null }).nativeElement.textContent).toContain('Sin datos');
    TestBed.resetTestingModule();
    expect(render(TodayPanelComponent, { title: 'Llegadas', icon: 'login', items: [], emptyText: 'Sin llegadas hoy' }).nativeElement.textContent).toContain('Sin llegadas hoy');
  });
  it('lists only room numbers for maintenance', () => {
    const f = render(MaintenancePanelComponent, { rooms: [{ id: 5, number: '105' }] });
    expect(f.nativeElement.querySelector('.h-chip')?.textContent?.trim()).toBe('105');
    TestBed.resetTestingModule();
    expect(render(MaintenancePanelComponent, { rooms: null }).nativeElement.textContent).toContain('Sin datos');
  });
});

describe('navigation components', () => {
  it('sidebar renders only the groups it is given, with labelled controls', () => {
    const f = render(NextSidebarComponent, { groups: buildNav(false), dark: false }, [provideRouter([])]);
    const text: string = f.nativeElement.textContent;
    expect(text).toContain('Huéspedes');
    expect(text).not.toContain('Caja y gastos');
    expect(text).toContain('Cerrar sesión');
    expect(f.nativeElement.querySelector('nav')?.getAttribute('aria-label')).toBe('Menú principal');
  });
  it('bottom nav has a labelled "+" for expenses and emits', () => {
    const f = render(BottomNavComponent, {}, [provideRouter([])]);
    let fired = 0; f.componentInstance.expense.subscribe(() => fired++);
    const plus = f.nativeElement.querySelector('.h-bottomnav__plus') as HTMLButtonElement;
    expect(plus.getAttribute('aria-label')).toBe('Registrar gasto');
    plus.click();
    expect(fired).toBe(1);
  });
});
