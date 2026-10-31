import { TestBed } from '@angular/core/testing';
import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TenantService } from 'core-auth';
import { AiChatComponent } from './ai-chat.component';
import { AiService } from '../../services/ai.service';
import { CHAT_CONFIG_TOKEN } from '../../tokens/chat.token';
import { ChatConfig } from '../../interfaces/chat-config';

function create(config: Partial<ChatConfig> = {}) {
  TestBed.configureTestingModule({
    providers: [
      AiService,
      provideHttpClient(),
      provideHttpClientTesting(),
      { provide: TenantService, useValue: { activeTenant: () => ({ id_company: 7 }) } },
      { provide: CHAT_CONFIG_TOKEN, useValue: { apiUrl_ai: 'http://localhost:test/chat', title: 'T', logoUrl: '', primaryColor: '', ...config } }
    ]
  });
  const fixture = TestBed.createComponent(AiChatComponent);
  fixture.componentInstance.isOpen.set(true);
  fixture.detectChanges();
  return { fixture, cmp: fixture.componentInstance, http: TestBed.inject(HttpTestingController) };
}

function pick(cmp: AiChatComponent, file: File) {
  const input = { files: [file], value: 'x' } as unknown as HTMLInputElement;
  cmp.onFileSelected({ target: input } as unknown as Event);
}

const png = () => new File([new Uint8Array(10)], 'p.png', { type: 'image/png' });

describe('AiChatComponent attachments', () => {
  let create$: ReturnType<typeof vi.fn>;
  let revoke: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    create$ = vi.fn(() => 'blob:preview');
    revoke = vi.fn();
    (URL as unknown as { createObjectURL: unknown }).createObjectURL = create$;
    (URL as unknown as { revokeObjectURL: unknown }).revokeObjectURL = revoke;
  });

  it('renders no paperclip or file input with the defaults', () => {
    const { fixture } = create();
    const el: HTMLElement = fixture.nativeElement;
    expect(el.querySelector('.btn-attach')).toBeNull();
    expect(el.querySelector('input[type=file]')).toBeNull();
  });

  it('renders an accessible paperclip when enabled', () => {
    const { fixture } = create({ attachments: { enabled: true } });
    const btn: HTMLButtonElement = fixture.nativeElement.querySelector('.btn-attach');
    expect(btn.getAttribute('aria-label')).toBe('Adjuntar archivo');
    expect(btn.tagName).toBe('BUTTON');
  });

  it('rejects a wrong type and an oversized file with an inline error', () => {
    const { fixture, cmp } = create({ attachments: { enabled: true, maxSizeMb: 1 } });
    pick(cmp, new File(['x'], 'run.exe', { type: 'application/x-msdownload' }));
    expect(cmp.selectedFile()).toBeNull();
    expect(cmp.attachmentError()).toContain('Tipo de archivo no permitido');

    const big = new File(['x'], 'big.pdf', { type: 'application/pdf' });
    Object.defineProperty(big, 'size', { value: 1024 * 1024 + 1 });
    pick(cmp, big);
    expect(cmp.selectedFile()).toBeNull();
    expect(cmp.attachmentError()).toContain('1 MB');
    fixture.detectChanges();
    expect(fixture.nativeElement.querySelector('[role=alert]')).not.toBeNull();
  });

  it('does not accept a generic type unless the extension maps to an accepted one', () => {
    const { cmp } = create({ attachments: { enabled: true } });
    pick(cmp, new File(['x'], 'a.exe', { type: 'application/octet-stream' }));
    expect(cmp.selectedFile()).toBeNull();
    pick(cmp, new File(['x'], 'a.pdf', { type: 'text/plain' }));
    expect(cmp.selectedFile()).toBeNull();
  });

  it('resolves the type from the extension when the MIME is empty', () => {
    const { cmp } = create({ attachments: { enabled: true } });
    pick(cmp, new File(['<a/>'], 'factura.XML', { type: '' }));
    expect(cmp.selectedFile()?.name).toBe('factura.XML');
    expect(cmp.selectedType()).toBe('text/xml');
    pick(cmp, new File(['x'], 'foto.jpg', { type: 'application/octet-stream' }));
    expect(cmp.selectedType()).toBe('image/jpeg');
  });

  it('honours a custom accept list when mapping extensions', () => {
    const { cmp } = create({ attachments: { enabled: true, accept: ['application/pdf'] } });
    pick(cmp, new File(['<a/>'], 'f.xml', { type: '' }));
    expect(cmp.selectedFile()).toBeNull();
  });

  it('revokes the preview URL on remove', () => {
    const { cmp } = create({ attachments: { enabled: true } });
    pick(cmp, png());
    expect(cmp.previewUrl()).toBe('blob:preview');
    cmp.removeFile();
    expect(revoke).toHaveBeenCalledWith('blob:preview');
    expect(cmp.selectedFile()).toBeNull();
    expect(cmp.previewUrl()).toBeNull();
  });

  it('revokes the preview URL on send and on destroy', async () => {
    const { fixture, cmp, http } = create({ attachments: { enabled: true } });
    pick(cmp, png());
    cmp.userInput = 'mira';
    const sending = cmp.send();
    expect(revoke).toHaveBeenCalledWith('blob:preview');
    await new Promise(r => setTimeout(r, 0));
    http.expectOne('http://localhost:test/chat').flush({ output: 'ok' });
    await sending;
    expect(cmp.selectedFile()).toBeNull();
    expect(cmp.userInput).toBe('');

    pick(cmp, png());
    revoke.mockClear();
    fixture.destroy();
    expect(revoke).toHaveBeenCalledWith('blob:preview');
  });

  it('keeps the draft and the file after an HTTP error so the user can retry', async () => {
    const { cmp, http } = create({ attachments: { enabled: true } });
    const file = png();
    pick(cmp, file);
    cmp.userInput = 'mira';
    const sending = cmp.send();
    await new Promise(r => setTimeout(r, 0));
    http.expectOne('http://localhost:test/chat').flush('x', { status: 500, statusText: 'err' });
    await sending;
    expect(cmp.userInput).toBe('mira');
    expect(cmp.selectedFile()).toBe(file);
    expect(cmp.previewUrl()).toBe('blob:preview');
  });

  it('strips control characters and caps the displayed name', () => {
    const { cmp } = create({ attachments: { enabled: true } });
    expect(cmp.displayName({ name: 'a\u0000b‮c.xml' })).toBe('abc.xml');
    expect(cmp.displayName({ name: 'a'.repeat(300) }).length).toBe(255);
  });
});
