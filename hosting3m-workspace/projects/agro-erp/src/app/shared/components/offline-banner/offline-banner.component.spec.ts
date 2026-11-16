import { TestBed } from '@angular/core/testing';
import { signal } from '@angular/core';
import { OfflineSessionService } from '@core/services/offline-session.service';
import { OfflineBannerComponent } from './offline-banner.component';

const session = { state: signal<'valid' | 'grace' | 'expired'>('valid') };

beforeEach(() => {
  session.state.set('valid');
  TestBed.configureTestingModule({ providers: [{ provide: OfflineSessionService, useValue: session }] });
});

describe('OfflineBannerComponent', () => {
  function render(served: boolean, savedAt: string | null): HTMLElement {
    const fixture = TestBed.createComponent(OfflineBannerComponent);
    fixture.componentRef.setInput('servedFromCache', served);
    fixture.componentRef.setInput('savedAt', savedAt);
    fixture.detectChanges();
    return fixture.nativeElement;
  }

  it('is hidden when not served from cache', () => {
    expect(render(false, '2026-11-16T10:00:00Z').querySelector('.alert')).toBeNull();
  });

  it('is visible with the Spanish message when served from cache', () => {
    const el = render(true, '2026-11-16T10:00:00Z');
    expect(el.textContent).toContain('Mostrando datos guardados el');
    expect(el.textContent).toContain('los cambios no se guardarán');
  });

  it('in grace says the session expired and that changes are not saved until an online login', () => {
    session.state.set('grace');
    const text = render(true, '2026-11-16T10:00:00Z').textContent ?? '';
    expect(text).toContain('Sesión vencida');
    expect(text).toContain('iniciar sesión en línea');
  });

  it('omits the date when savedAt is missing or invalid', () => {
    expect(render(true, null).textContent).toContain('Mostrando datos guardados.');
    expect(render(true, 'garbage').textContent).toContain('Mostrando datos guardados.');
  });
});
