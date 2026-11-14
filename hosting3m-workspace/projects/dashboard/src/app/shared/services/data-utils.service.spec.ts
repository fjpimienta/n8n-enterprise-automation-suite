import { TestBed } from '@angular/core/testing';

import { DateUtilsService, toLocalDateString } from './data-utils.service';

describe('DateUtilsService', () => {
  let service: DateUtilsService;

  beforeEach(() => {
    TestBed.configureTestingModule({});
    service = TestBed.inject(DateUtilsService);
  });

  afterEach(() => vi.useRealTimers());

  it('should be created', () => {
    expect(service).toBeTruthy();
  });

  it('uses the local calendar day, not the UTC day (18:30 local, UTC-6)', () => {
    // Local 18:30 on Dec 1 in UTC-6 is 00:30Z on Dec 2; built from local fields so it is TZ-independent.
    const local = new Date(2026, 11, 1, 18, 30);
    expect(toLocalDateString(local)).toBe('2026-12-01');
    vi.useFakeTimers();
    vi.setSystemTime(local);
    expect(service.todayStr).toBe('2026-12-01');
    expect(service.formatToInputDate(local)).toBe('2026-12-01');
  });

  it('pads month and day', () => {
    expect(toLocalDateString(new Date(2026, 0, 5, 23, 59))).toBe('2026-01-05');
  });
});
