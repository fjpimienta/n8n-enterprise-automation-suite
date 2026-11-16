import { ComponentFixture, TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { environment } from '@env/environment';
import { ComplianceService } from '../../services/compliance.service';
import { UppComplianceListComponent } from './upp-compliance-list.component';

const UPP_URL = `${environment.apiUrl_crud}/upp_compliance_status`;
const PSG_URL = `${environment.apiUrl_crud}/psg_compliance_status`;

describe('UppComplianceListComponent', () => {
  let fixture: ComponentFixture<UppComplianceListComponent>;
  let httpMock: HttpTestingController;

  beforeEach(() => {
    TestBed.configureTestingModule({
      imports: [UppComplianceListComponent],
      providers: [provideRouter([]), provideHttpClient(), provideHttpClientTesting()]
    });
    httpMock = TestBed.inject(HttpTestingController);
    fixture = TestBed.createComponent(UppComplianceListComponent);
    fixture.detectChanges(); // loads UPP only
  });

  afterEach(() => httpMock.verify());

  const el = (): HTMLElement => fixture.nativeElement;

  it('only loads the UPP status, never the PSG status', () => {
    httpMock.expectNone(PSG_URL);
    httpMock.expectOne(UPP_URL).flush({ error: false, operation: 'getall', message: '', data: [] });
  });

  it('shows the UPP error when the UPP load fails', () => {
    httpMock.expectOne(UPP_URL).flush(null, { status: 500, statusText: 'Error' });
    fixture.detectChanges();
    expect(el().querySelector('.alert-danger')?.textContent).toContain('No se pudo conectar con el servicio de cumplimiento normativo.');
  });

  it('does not show any error when only the PSG load fails', () => {
    // A PSG failure is shown only on the card. This screen is UPP-only.
    httpMock.expectOne(UPP_URL).flush({ error: false, operation: 'getall', message: '', data: [] });
    fixture.detectChanges();

    TestBed.inject(ComplianceService).loadPsgStatus();
    httpMock.expectOne(PSG_URL).flush(null, { status: 500, statusText: 'Error' });
    fixture.detectChanges();

    expect(el().querySelector('.alert-danger')).toBeNull();
  });
});
