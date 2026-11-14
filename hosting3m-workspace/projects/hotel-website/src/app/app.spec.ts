import { TestBed } from '@angular/core/testing';
import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { App } from './app';

describe('App', () => {
  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [App],
    }).compileComponents();
  });

  it('should create the app', () => {
    const fixture = TestBed.createComponent(App);
    const app = fixture.componentInstance;
    expect(app).toBeTruthy();
  });

  it('should render title', async () => {
    const fixture = TestBed.createComponent(App);
    await fixture.whenStable();
    const compiled = fixture.nativeElement as HTMLElement;
    expect(compiled.querySelector('h1')?.textContent).toContain('Hello, hotel-website');
  });
});

describe('App.submitForm', () => {
  let app: App;
  let http: HttpTestingController;

  beforeEach(() => {
    TestBed.configureTestingModule({
      imports: [App],
      providers: [provideHttpClient(), provideHttpClientTesting()],
    });
    app = TestBed.createComponent(App).componentInstance;
    http = TestBed.inject(HttpTestingController);
    vi.spyOn(console, 'error').mockImplementation(() => {});
  });

  const submit = (body: unknown, opts?: { status: number; statusText: string }) => {
    app.submitForm();
    const req = http.expectOne((r) => r.url.endsWith('/lead'));
    req.flush(body, opts);
  };

  it('sets success only for status success with a booking_id', () => {
    submit({ status: 'success', booking_id: 30 });
    expect(app.formStatus()).toBe('success');
    expect(app.isSubmitting()).toBe(false);
  });

  it('sets error on an empty 200 body', () => {
    submit(null);
    expect(app.formStatus()).toBe('error');
    expect(app.isSubmitting()).toBe(false);
  });

  it('sets error on a 200 body without booking_id or with error: true', () => {
    submit({ status: 'success' });
    expect(app.formStatus()).toBe('error');
    app.submitForm();
    http.expectOne((r) => r.url.endsWith('/lead')).flush({ error: true });
    expect(app.formStatus()).toBe('error');
  });

  it('sets error when the endpoint is down (HTTP 500)', () => {
    submit('fail', { status: 500, statusText: 'Server Error' });
    expect(app.formStatus()).toBe('error');
    expect(app.isSubmitting()).toBe(false);
  });
});
