import { ComponentFixture, TestBed } from '@angular/core/testing';
import { Router, provideRouter } from '@angular/router';
import { signal } from '@angular/core';
import { PinCreateResult, PinLockService } from '@core/services/pin-lock.service';
import { OfflineSessionService } from '@core/services/offline-session.service';
import { PinSetupComponent } from './pin-setup.component';

describe('PinSetupComponent', () => {
  let fixture: ComponentFixture<PinSetupComponent>;
  let createPin: ReturnType<typeof vi.fn>;
  let navigate: ReturnType<typeof vi.spyOn>;

  async function create(result: PinCreateResult = 'created', online = true): Promise<void> {
    createPin = vi.fn(async () => result);
    TestBed.resetTestingModule();
    TestBed.configureTestingModule({
      imports: [PinSetupComponent],
      providers: [
        provideRouter([{ path: '', children: [] }]),
        { provide: PinLockService, useValue: { createPin } },
        { provide: OfflineSessionService, useValue: { online: signal(online) } },
      ],
    });
    navigate = vi.spyOn(TestBed.inject(Router), 'navigateByUrl').mockResolvedValue(true);
    fixture = TestBed.createComponent(PinSetupComponent);
    fixture.detectChanges();
  }

  function fill(pin: string, confirm: string): void {
    const el = fixture.nativeElement as HTMLElement;
    const a = el.querySelector('#pin-new') as HTMLInputElement;
    const b = el.querySelector('#pin-confirm') as HTMLInputElement;
    a.value = pin; a.dispatchEvent(new Event('input'));
    b.value = confirm; b.dispatchEvent(new Event('input'));
    fixture.detectChanges();
  }

  async function submit(): Promise<void> {
    (fixture.nativeElement as HTMLElement).querySelector('form')!.dispatchEvent(new Event('submit'));
    await fixture.whenStable();
    fixture.detectChanges();
  }

  it('refuses mismatched confirmation without calling the service', async () => {
    await create();
    fill('482915', '482916');
    await submit();
    expect(createPin).not.toHaveBeenCalled();
    expect((fixture.nativeElement as HTMLElement).textContent).toContain('Los PIN no coinciden.');
  });

  it('shows the trivial-PIN message and stays on the page', async () => {
    await create('trivial');
    fill('123456', '123456');
    await submit();
    expect(createPin).toHaveBeenCalledWith('123456');
    expect((fixture.nativeElement as HTMLElement).textContent).toContain('menos predecible');
    expect(navigate).not.toHaveBeenCalled();
  });

  it('a created PIN goes back to the dashboard', async () => {
    await create('created');
    fill('482915', '482915');
    await submit();
    expect(navigate).toHaveBeenCalledWith('/');
  });

  it('the save button stays disabled offline', async () => {
    await create('created', false);
    fill('482915', '482915');
    const button = (fixture.nativeElement as HTMLElement).querySelector('button[type="submit"]') as HTMLButtonElement;
    expect(button.disabled).toBe(true);
  });
});
