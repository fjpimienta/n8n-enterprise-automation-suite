import { describe, expect, it, vi } from 'vitest';
import { HomeNextComponent } from './home-next.component';

/**
 * The home page extends the classic dashboard component, which is too heavy to build in a unit test. The three
 * overrides only use a few collaborators, so they are called on a minimal stand-in.
 */
function ctx(role: string | null, superMark = vi.fn(async () => undefined)) {
  return {
    nextRouter: { navigate: vi.fn(async () => true) },
    nextAuth: { currentUser: () => (role === null ? null : { role }) },
    hotelService: { clearSelection: vi.fn(), finishMaintenance: vi.fn(), selectedRoom: () => ({ id: 1, room_number: '105' }) },
    bookingService: { updateCleaningStatus: vi.fn() },
    superMark
  };
}
const proto = HomeNextComponent.prototype as any;

describe('HomeNextComponent: classic shortcuts are routed through the rules', () => {
  it('"Mantenimiento abierto" opens the board and never the classic monitor modal', () => {
    const c = ctx('ADMIN');
    proto.onMaintenanceSelect.call(c, 5);
    expect(c.nextRouter.navigate).toHaveBeenCalledWith(['/dashboard/mantenimiento']);
    expect((c as any).showMaintenanceMonitor).toBeUndefined();
  });

  it('the classic "Finalizar mantenimiento" button writes nothing: it clears the selection and goes to the board', async () => {
    const c = ctx('ADMIN');
    await proto.handleFinishMaintenance.call(c);
    expect(c.hotelService.finishMaintenance).not.toHaveBeenCalled();
    expect(c.hotelService.clearSelection).toHaveBeenCalled();
    expect(c.nextRouter.navigate).toHaveBeenCalledWith(['/dashboard/mantenimiento']);
  });

  it('marking a room clean from the room detail is refused for roles without permission, with an alert and no write', async () => {
    const alertSpy = vi.spyOn(window, 'alert').mockImplementation(() => undefined);
    for (const role of ['CUSTOMER', 'MAINTENANCE', null]) {
      const c = ctx(role);
      await proto.markRoomAsClean.call(c);
      expect(c.bookingService.updateCleaningStatus).not.toHaveBeenCalled();
    }
    expect(alertSpy).toHaveBeenCalledTimes(3);
    expect(alertSpy.mock.calls[0][0]).toBe('Tu rol no puede marcar habitaciones como limpias.');
    alertSpy.mockRestore();
  });
});
