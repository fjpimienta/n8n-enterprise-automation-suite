import { ComponentFixture, TestBed } from '@angular/core/testing';
import { Router, provideRouter } from '@angular/router';
import { signal } from '@angular/core';
import { AuthService } from 'core-auth';
import { PinLockService, PinVerifyResult } from '@core/services/pin-lock.service';
import { OfflineSessionService } from '@core/services/offline-session.service';
import { UnlockComponent } from './unlock.component';

/** Lets pending promises (ngOnInit, verify) and the signal updates they cause run. */
const settle = () => new Promise(resolve => setTimeout(resolve, 0));

describe('UnlockComponent', () => {
  let fixture: ComponentFixture<UnlockComponent>;
  let pinLock: { hasRecord: ReturnType<typeof vi.fn>; remainingAttempts: ReturnType<typeof vi.fn>; verify: ReturnType<typeof vi.fn> };
  let session: { online: ReturnType<typeof signal<boolean>>; unlock: ReturnType<typeof vi.fn> };
  let auth: { logout: ReturnType<typeof vi.fn> };
  let navigate: ReturnType<typeof vi.spyOn>;

  async function create(opts: { hasRecord: boolean; online?: boolean; verify?: PinVerifyResult }): Promise<void> {
    pinLock = {
      hasRecord: vi.fn(async () => opts.hasRecord),
      remainingAttempts: vi.fn(async () => (opts.hasRecord ? 5 : null)),
      verify: vi.fn(async () => opts.verify ?? { status: 'ok' }),
    };
    session = { online: signal(opts.online ?? true), unlock: vi.fn(() => true) };
    auth = { logout: vi.fn() };
    TestBed.resetTestingModule();
    TestBed.configureTestingModule({
      imports: [UnlockComponent],
      providers: [
        provideRouter([{ path: '', children: [] }, { path: 'login', children: [] }]),
        { provide: PinLockService, useValue: pinLock },
        { provide: OfflineSessionService, useValue: session },
        { provide: AuthService, useValue: auth },
      ],
    });
    navigate = vi.spyOn(TestBed.inject(Router), 'navigateByUrl').mockResolvedValue(true);
    fixture = TestBed.createComponent(UnlockComponent);
    await settle();
    fixture.detectChanges();
  }

  const el = () => fixture.nativeElement as HTMLElement;
  const text = () => el().textContent ?? '';

  it('shows the PIN form when a record exists', async () => {
    await create({ hasRecord: true });
    expect(el().querySelector('#unlock-pin')).not.toBeNull();
    expect(text()).toContain('Intentos restantes: 5');
  });

  it('a wrong PIN shows the remaining attempts and does not unlock', async () => {
    await create({ hasRecord: true, verify: { status: 'wrong', remainingAttempts: 4 } });
    const input = el().querySelector('#unlock-pin') as HTMLInputElement;
    input.value = '193847';
    input.dispatchEvent(new Event('input'));
    el().querySelector('form')!.dispatchEvent(new Event('submit'));
    await settle();
    fixture.detectChanges();
    expect(pinLock.verify).toHaveBeenCalledWith('193847');
    expect(text()).toContain('Te quedan 4 intento(s).');
    expect(session.unlock).not.toHaveBeenCalled();
    expect(navigate).not.toHaveBeenCalled();
  });

  it('the right PIN unlocks the session and goes home', async () => {
    await create({ hasRecord: true, verify: { status: 'ok' } });
    const input = el().querySelector('#unlock-pin') as HTMLInputElement;
    input.value = '482915';
    input.dispatchEvent(new Event('input'));
    el().querySelector('form')!.dispatchEvent(new Event('submit'));
    await settle();
    expect(session.unlock).toHaveBeenCalled();
    expect(navigate).toHaveBeenCalledWith('/');
  });

  it('without a record there is no PIN form, only the online login path', async () => {
    await create({ hasRecord: false });
    expect(el().querySelector('#unlock-pin')).toBeNull();
    expect(text()).toContain('No hay PIN configurado');
    expect(text()).toContain('Iniciar sesión');
  });

  it('offline: no "Iniciar sesión" button, and the screen says so', async () => {
    await create({ hasRecord: true, online: false });
    expect(text()).not.toContain('Iniciar sesión');
    expect(text()).toContain('Sin conexión');
  });

  it('"Iniciar sesión" goes to /login WITHOUT logging out (the cache and PIN survive a failed login)', async () => {
    await create({ hasRecord: false, online: true });
    const button = Array.from(el().querySelectorAll('button')).find(b => b.textContent?.includes('Iniciar sesión'))!;
    button.click();
    expect(auth.logout).not.toHaveBeenCalled();
    expect(navigate).toHaveBeenCalledWith('/login');
  });

  it('explains that a failed login keeps the copy and the PIN, and that another user wipes it', async () => {
    await create({ hasRecord: true, online: true });
    expect(text()).toContain('tu copia y tu PIN se conservan');
    expect(text()).toContain('otro usuario');
  });

  it('a locked-out record shows the lockout message and no form', async () => {
    await create({ hasRecord: true, verify: { status: 'locked' } });
    const input = el().querySelector('#unlock-pin') as HTMLInputElement;
    input.value = '193847';
    input.dispatchEvent(new Event('input'));
    el().querySelector('form')!.dispatchEvent(new Event('submit'));
    await settle();
    fixture.detectChanges();
    expect(text()).toContain('Demasiados intentos fallidos');
    expect(el().querySelector('#unlock-pin')).toBeNull();
  });
});
