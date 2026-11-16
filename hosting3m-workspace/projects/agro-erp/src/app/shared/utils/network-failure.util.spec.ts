import { HttpErrorResponse } from '@angular/common/http';
import { isNetworkFailure } from './network-failure.util';

describe('isNetworkFailure', () => {
  afterEach(() => vi.restoreAllMocks());

  it('is true for HttpErrorResponse status 0', () => {
    expect(isNetworkFailure(new HttpErrorResponse({ status: 0 }))).toBe(true);
  });

  it('is false for HTTP errors while online', () => {
    vi.spyOn(navigator, 'onLine', 'get').mockReturnValue(true);
    for (const status of [400, 401, 403, 500, 503]) {
      expect(isNetworkFailure(new HttpErrorResponse({ status }))).toBe(false);
    }
  });

  it('is false for a gateway error:true Error while online', () => {
    vi.spyOn(navigator, 'onLine', 'get').mockReturnValue(true);
    expect(isNetworkFailure(new Error('gateway error'))).toBe(false);
  });

  it('is true when the browser reports offline', () => {
    vi.spyOn(navigator, 'onLine', 'get').mockReturnValue(false);
    expect(isNetworkFailure(new Error('x'))).toBe(true);
  });
});
