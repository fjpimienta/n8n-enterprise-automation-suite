import { describe, it, expect } from 'vitest';
import { ConfirmActionModalComponent } from './confirm-action-modal.component';

/** Class-level checks (no TestBed): the typed reason must survive a confirm that fails server-side. */
describe('ConfirmActionModalComponent', () => {
  const setup = () => {
    const modal = new ConfirmActionModalComponent();
    modal.notesRequired = true;
    const emitted: { notas?: string }[] = [];
    modal.confirm.subscribe(e => emitted.push(e));
    return { modal, emitted };
  };

  it('keeps the typed reason after confirming (the parent may keep the modal open on error)', () => {
    const { modal, emitted } = setup();
    modal.notas.set('  El comprador se retractó  ');
    modal.onConfirm();
    expect(emitted).toEqual([{ notas: 'El comprador se retractó' }]);
    expect(modal.notas()).toBe('  El comprador se retractó  ');
    expect(modal.hasNotes()).toBe(true); // confirm button stays enabled for a retry
  });

  it('does not emit while busy or without the required reason', () => {
    const { modal, emitted } = setup();
    modal.onConfirm();
    modal.notas.set('Motivo');
    modal.busy = true;
    modal.onConfirm();
    expect(emitted).toEqual([]);
  });
});
