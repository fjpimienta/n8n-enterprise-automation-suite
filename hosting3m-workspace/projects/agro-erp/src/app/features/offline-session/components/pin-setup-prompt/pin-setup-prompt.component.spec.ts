import { ComponentFixture, TestBed } from '@angular/core/testing';
import { Router, provideRouter } from '@angular/router';
import { signal } from '@angular/core';
import { PinLockService } from '@core/services/pin-lock.service';
import { OfflineSessionService } from '@core/services/offline-session.service';
import { PinSetupPromptComponent } from './pin-setup-prompt.component';

/** Lets pending promises (hasRecord, navigation) and the signal updates they cause run. */
const settle = () => new Promise(resolve => setTimeout(resolve, 0));

describe('PinSetupPromptComponent', () => {
  let fixture: ComponentFixture<PinSetupPromptComponent>;
  let router: Router;
  let hasRecord: boolean;
  let state: 'valid' | 'grace' | 'expired';
  let online: ReturnType<typeof signal<boolean>>;

  /** Mounts the component the way the main layout does: inside a real router, outside any injection context. */
  async function mount(): Promise<void> {
    TestBed.resetTestingModule();
    TestBed.configureTestingModule({
      imports: [PinSetupPromptComponent],
      providers: [
        provideRouter([{ path: '', children: [] }, { path: 'a', children: [] }, { path: 'seguridad/pin', children: [] }]),
        { provide: PinLockService, useValue: { hasRecord: async () => hasRecord } },
        { provide: OfflineSessionService, useValue: { readState: () => state, online } },
      ],
    });
    router = TestBed.inject(Router);
    await router.navigateByUrl('/');
    fixture = TestBed.createComponent(PinSetupPromptComponent);
    fixture.detectChanges(); // runs ngOnInit
    await settle();
    fixture.detectChanges();
  }

  const el = () => fixture.nativeElement as HTMLElement;
  const prompt = () => el().querySelector('[aria-label="Crear PIN sin conexión"]');

  beforeEach(() => {
    hasRecord = false;
    state = 'valid';
    online = signal(true);
  });

  it('renders and shows the prompt when valid, online and there is no PIN record', async () => {
    await mount();
    expect(prompt()).not.toBeNull();
    expect(el().querySelector('a[href="/seguridad/pin"]')).not.toBeNull();
  });

  it('is hidden when a PIN record already exists', async () => {
    hasRecord = true;
    await mount();
    expect(prompt()).toBeNull();
  });

  it('is hidden when offline', async () => {
    online.set(false);
    await mount();
    expect(prompt()).toBeNull();
  });

  it('is hidden when the session is not valid (grace or expired)', async () => {
    state = 'grace';
    await mount();
    expect(prompt()).toBeNull();
    state = 'expired';
    fixture.destroy();
    await mount();
    expect(prompt()).toBeNull();
  });

  it('"Ahora no" hides it and it stays hidden on later navigations in this page session', async () => {
    await mount();
    (el().querySelector('button') as HTMLButtonElement).click();
    fixture.detectChanges();
    expect(prompt()).toBeNull();
    await router.navigateByUrl('/a');
    await settle();
    fixture.detectChanges();
    expect(prompt()).toBeNull();
  });

  it('re-checks on NavigationEnd: appears after the record is removed, disappears once it exists', async () => {
    hasRecord = true;
    await mount();
    expect(prompt()).toBeNull();

    hasRecord = false;
    await router.navigateByUrl('/a');
    await settle();
    fixture.detectChanges();
    expect(prompt()).not.toBeNull();

    hasRecord = true;
    await router.navigateByUrl('/');
    await settle();
    fixture.detectChanges();
    expect(prompt()).toBeNull();
  });
});
