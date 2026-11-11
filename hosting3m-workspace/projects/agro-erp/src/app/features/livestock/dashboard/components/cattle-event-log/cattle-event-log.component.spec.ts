import { TestBed } from '@angular/core/testing';
import { signal } from '@angular/core';
import { TenantService } from 'core-auth';
import { CattleApiService } from '@core/services/cattle-api.service';
import { CattleEventLogComponent } from './cattle-event-log.component';

const animal = (id: string) => ({ id, rfid_siniiga: id, numero_fuego: null } as any);

const row = (id: string, livestock_id: string, event_type: string, description: string | null = null) => ({
  id,
  tenant_id: 3,
  livestock_id,
  rfid_siniiga: livestock_id,
  numero_fuego: null,
  event_type,
  event_date: '2026-11-01T10:00:00',
  created_at: '2026-11-01T10:00:00',
  description
});

describe('CattleEventLogComponent — REGULARIZACION event type', () => {
  async function setup(rows: any[]) {
    TestBed.configureTestingModule({
      providers: [
        { provide: TenantService, useValue: { activeTenantId: signal(3) } },
        { provide: CattleApiService, useValue: { getCattleEventLog: () => Promise.resolve(rows) } }
      ]
    });
    const fixture = TestBed.createComponent(CattleEventLogComponent);
    fixture.componentRef.setInput('cattleData', [animal('A1'), animal('A2')]);
    fixture.componentRef.setInput('moduleCattleData', [animal('A1'), animal('A2')]);
    fixture.detectChanges();
    await fixture.whenStable();
    fixture.detectChanges();
    return fixture;
  }

  it('has a label for REGULARIZACION', async () => {
    const fixture = await setup([]);
    expect(fixture.componentInstance.eventTypeLabel['REGULARIZACION']).toBe('Regularización');
  });

  it('shows a REGULARIZACION entry with its label, badge class and description', async () => {
    const fixture = await setup([row('r1', 'A1', 'REGULARIZACION', 'Alta por regularización de padrón — Guía: G-1')]);
    const entries = fixture.componentInstance.entries();
    expect(entries.length).toBe(1);
    expect(entries[0].eventType).toBe('REGULARIZACION');

    const el: HTMLElement = fixture.nativeElement;
    expect(el.textContent).toContain('Regularización');
    expect(el.textContent).toContain('Guía: G-1');
    expect(el.querySelector('.badge.bg-secondary-lt')).not.toBeNull();
  });

  it('keeps COMPRA and other types alongside REGULARIZACION', async () => {
    const fixture = await setup([
      row('c1', 'A1', 'COMPRA', 'Comprado a X'),
      row('p1', 'A2', 'PESO'),
      row('r1', 'A2', 'REGULARIZACION', 'Alta')
    ]);
    const types = fixture.componentInstance.entries().map(e => e.eventType).sort();
    expect(types).toEqual(['COMPRA', 'PESO', 'REGULARIZACION']);
  });

  it('filters by REGULARIZACION', async () => {
    const fixture = await setup([row('c1', 'A1', 'COMPRA'), row('r1', 'A2', 'REGULARIZACION', 'Alta')]);
    fixture.componentInstance.setEventTypeFilter('REGULARIZACION');
    const filtered = fixture.componentInstance.filteredEntries();
    expect(filtered.length).toBe(1);
    expect(filtered[0].eventType).toBe('REGULARIZACION');
  });

  it('exports the description of a REGULARIZACION entry in the CSV detail', async () => {
    const fixture = await setup([row('r1', 'A1', 'REGULARIZACION', 'Alta por regularización')]);
    const component: any = fixture.componentInstance;
    expect(component.describeEntry(component.entries()[0])).toBe('Alta por regularización');
  });

  describe('unknown event types', () => {
    const rows = () => [
      row('c1', 'A1', 'COMPRA', 'Comprado a X'),
      row('u1', 'A2', 'TIPO_INVENTADO', 'Detalle del tipo nuevo'),
      row('p1', 'A1', 'PESO')
    ];

    it('shows the raw type as label and a neutral badge', async () => {
      const fixture = await setup(rows());
      const c = fixture.componentInstance;
      expect(c.typeLabel('TIPO_INVENTADO')).toBe('TIPO_INVENTADO');
      expect(c.isKnownType('TIPO_INVENTADO')).toBe(false);
      expect(c.isKnownType('COMPRA')).toBe(true);

      const el: HTMLElement = fixture.nativeElement;
      expect(el.textContent).toContain('TIPO_INVENTADO');
      expect(el.textContent).toContain('Detalle del tipo nuevo');
      const badges = Array.from(el.querySelectorAll('.badge')).filter(b => b.textContent?.trim() === 'TIPO_INVENTADO');
      expect(badges.length).toBe(1);
      expect(badges[0].classList.contains('bg-secondary-lt')).toBe(true);
    });

    it('sorts by event type in both directions without throwing', async () => {
      const fixture = await setup(rows());
      const c = fixture.componentInstance;
      c.setSort('eventType');
      expect(() => c.sortedEntries()).not.toThrow();
      expect(c.sortedEntries().length).toBe(3);
      c.setSort('eventType');
      expect(() => c.sortedEntries()).not.toThrow();
      expect(() => fixture.detectChanges()).not.toThrow();
    });

    it('groups by event type using the raw type as group name', async () => {
      const fixture = await setup(rows());
      const c = fixture.componentInstance;
      c.setGroupBy('EVENT_TYPE');
      const keys = c.groupedPageEntries().map(g => g.key);
      expect(keys).toContain('TIPO_INVENTADO');
      expect(keys).not.toContain('undefined');
      expect(() => fixture.detectChanges()).not.toThrow();
    });

    it('exports the raw type in the CSV type column', async () => {
      const fixture = await setup(rows());
      let captured: Blob | null = null;
      const originalCreate = (URL as any).createObjectURL;
      const originalRevoke = (URL as any).revokeObjectURL;
      (URL as any).createObjectURL = (b: Blob) => { captured = b; return 'blob:test'; };
      (URL as any).revokeObjectURL = () => {};
      const clickSpy = vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(() => {});
      try {
        expect(() => fixture.componentInstance.exportCsv()).not.toThrow();
      } finally {
        (URL as any).createObjectURL = originalCreate;
        (URL as any).revokeObjectURL = originalRevoke;
        clickSpy.mockRestore();
      }
      expect(captured).not.toBeNull();
      const text = await (captured as unknown as Blob).text();
      expect(text).toContain('"TIPO_INVENTADO"');
      expect(text).toContain('"Compra"');
    });
  });
});
