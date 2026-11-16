import { TestBed } from '@angular/core/testing';
import { LoginHandoffService } from './login-handoff.service';

describe('LoginHandoffService', () => {
  it('returns nothing when no login request was observed', () => {
    expect(TestBed.inject(LoginHandoffService).consume()).toBeNull();
  });

  it('hands the captured identity over once', () => {
    const svc = TestBed.inject(LoginHandoffService);
    svc.begin('ana');
    expect(svc.consume()).toEqual({ previousUser: 'ana' });
    expect(svc.consume()).toBeNull();
  });

  it('a later login request overwrites an earlier one (a failed attempt never leaves a stale value)', () => {
    const svc = TestBed.inject(LoginHandoffService);
    svc.begin('ana');
    svc.begin(null);
    expect(svc.consume()).toEqual({ previousUser: null });
  });
});
