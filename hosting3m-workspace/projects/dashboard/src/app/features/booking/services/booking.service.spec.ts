import { TestBed } from '@angular/core/testing';
import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TenantService } from 'core-auth';
import { of } from 'rxjs';

import { BookingService } from './booking.service';
import { AdminService } from '@features/admin/services/admin.service';
import { ReportService } from '@features/finance/services/report.service';

describe('BookingService', () => {
  let service: BookingService;
  let http: HttpTestingController;

  beforeEach(() => {
    TestBed.configureTestingModule({
      providers: [
        provideHttpClient(),
        provideHttpClientTesting(),
        { provide: AdminService, useValue: {
          getAuthHeaders: () => ({}),
          checkPossibleDuplicate: () => of({ data: [] }),
          generateInternalId: () => 'INT-1',
          generateDummyEmail: () => 'x@example.invalid',
        } },
        { provide: ReportService, useValue: {} },
        { provide: TenantService, useValue: { activeTenantId: () => 1 } },
      ],
    });
    service = TestBed.inject(BookingService);
    http = TestBed.inject(HttpTestingController);
    vi.spyOn(console, 'error').mockImplementation(() => {});
    vi.spyOn(window, 'alert').mockImplementation(() => {});
  });

  it('should be created', () => {
    expect(service).toBeTruthy();
  });

  // Silent Error Shield: HTTP 200 + error:true must reject (issue #1039).
  const cases: Array<[string, () => Promise<unknown>, string]> = [
    ['updateCleaningStatus', () => service.updateCleaningStatus(1, 'clean'), '/hotel_rooms'],
    ['updateReservation', () => service.updateReservation({ id: 1, amount_paid: 0, total_amount: 10 }), '/hotel_bookings'],
    ['registerPayment', () => service.registerPayment({ id: 1, amount_paid: 0, total_amount: 10, status: 'confirmed' }, 5), '/hotel_bookings'],
    ['cancelReservation', () => service.cancelReservation(1), '/hotel_bookings'],
    ['confirmPendingReservation', () => service.confirmPendingReservation(1), '/hotel_bookings'],
  ];

  for (const [name, call, path] of cases) {
    it(`${name} rejects on HTTP 200 with error:true`, async () => {
      const p = call();
      const assertion = expect(p).rejects.toThrow('boom');
      await Promise.resolve();
      http.expectOne(r => r.url.endsWith(path)).flush({ error: true, message: 'boom' });
      await assertion;
    });
  }

  it('createFutureReservation rejects when the booking insert returns error:true', async () => {
    const tick = () => new Promise(r => setTimeout(r));
    const p = service.createFutureReservation({
      full_name: 'Test Guest', check_in: '2026-12-01', check_out: '2026-12-02',
    }, 7);
    const assertion = expect(p).rejects.toThrow('boom');
    await tick();
    http.expectOne(r => r.url.endsWith('/hotel_bookings')).flush({ data: [] }); // isRoomFree
    await tick();
    http.expectOne(r => r.url.endsWith('/guests') || r.url.endsWith('/hotel_guests')).flush({ data: [{ id: 9 }] });
    await tick();
    http.expectOne(r => r.url.endsWith('/hotel_bookings')).flush({ error: true, message: 'boom' });
    await assertion;
  });

  it('registerPayment resolves on a normal response', async () => {
    const p = service.registerPayment({ id: 1, amount_paid: 0, total_amount: 10, status: 'confirmed' }, 5);
    await Promise.resolve();
    http.expectOne(r => r.url.endsWith('/hotel_bookings')).flush({ data: [{ id: 1 }] });
    await expect(p).resolves.toBeUndefined();
  });
});
