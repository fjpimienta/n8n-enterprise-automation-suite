import { TestBed } from '@angular/core/testing';
import { AiService } from './ai.service';
import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { CHAT_CONFIG_TOKEN } from 'ui-chat/tokens/chat.token';
import { TenantService } from 'core-auth';
import { ChatConfig } from '../interfaces/chat-config';

const URL_AI = 'http://localhost:test/chat';

function setup(config: Partial<ChatConfig> = {}) {
  TestBed.configureTestingModule({
    providers: [
      AiService,
      provideHttpClient(),
      provideHttpClientTesting(),
      { provide: TenantService, useValue: { activeTenant: () => ({ id_company: 7 }) } },
      { provide: CHAT_CONFIG_TOKEN, useValue: { apiUrl_ai: URL_AI, title: 'T', logoUrl: '', primaryColor: '', ...config } }
    ]
  });
  return { service: TestBed.inject(AiService), http: TestBed.inject(HttpTestingController) };
}

const flush = () => new Promise(r => setTimeout(r, 0));

describe('AiService', () => {
  it('should be created', () => {
    expect(setup().service).toBeTruthy();
  });

  it('without a file the body is byte-identical to the legacy one', () => {
    const { service, http } = setup();
    service.sendMessage('hola');
    const req = http.expectOne(URL_AI);
    const sessionId = (service as unknown as { sessionId: string }).sessionId;
    expect(JSON.stringify(req.request.body)).toBe(
      JSON.stringify({ chatInput: 'hola', sessionId, tenant_id: 7 })
    );
    req.flush({ output: 'ok' });
  });

  it('still ignores the file path when attachments are not enabled (defaults)', async () => {
    const { service, http } = setup();
    const ok = await service.sendMessage('hola', new File(['<a/>'], 'a.xml', { type: 'text/xml' }));
    expect(ok).toBe(false);
    http.expectNone(URL_AI);
    expect(service.messages().some(m => m.file)).toBe(false);
  });

  describe('with attachments enabled', () => {
    const enabled = { attachments: { enabled: true } };

    it('adds file {name,type,size,base64} to the same body and keeps Base64 out of the history', async () => {
      const { service, http } = setup(enabled);
      const promise = service.sendMessage('factura', new File(['<a/>'], 'inv.xml', { type: '' }));
      await flush();
      const req = http.expectOne(URL_AI);
      const body = req.request.body;
      expect(Object.keys(body)).toEqual(['chatInput', 'sessionId', 'tenant_id', 'file']);
      expect(body.tenant_id).toBe(7);
      expect(body.file).toEqual({ name: 'inv.xml', type: 'text/xml', size: 4, base64: btoa('<a/>') });
      expect(service.isLoading()).toBe(true);
      expect(service.messages().at(-1)?.file).toEqual({ name: 'inv.xml', type: 'text/xml', size: 4 });
      req.flush({ output: 'listo' });
      expect(await promise).toBe(true);
      expect(JSON.stringify(service.messages())).not.toContain(btoa('<a/>'));
      expect(service.isLoading()).toBe(false);
    });

    it('rejects an oversized file before reading it', async () => {
      const { service, http } = setup(enabled);
      const big = new File(['x'], 'big.pdf', { type: 'application/pdf' });
      Object.defineProperty(big, 'size', { value: 5 * 1024 * 1024 + 1 });
      const read = vi.spyOn(big, 'arrayBuffer');
      expect(await service.sendMessage('x', big)).toBe(false);
      expect(read).not.toHaveBeenCalled();
      http.expectNone(URL_AI);
    });

    it('re-checks the real byte length after reading', async () => {
      const { service, http } = setup(enabled);
      const liar = new File([new Uint8Array(100)], 'a.pdf', { type: 'application/pdf' });
      Object.defineProperty(liar, 'size', { value: 10 });
      vi.spyOn(liar, 'arrayBuffer').mockResolvedValue(new ArrayBuffer(5 * 1024 * 1024 + 1));
      expect(await service.sendMessage('x', liar)).toBe(false);
      http.expectNone(URL_AI);
    });

    it('on HTTP error rolls back the bubble, reports false and never logs or embeds the body', async () => {
      const { service, http } = setup(enabled);
      const spy = vi.spyOn(console, 'error').mockImplementation(() => undefined);
      const promise = service.sendMessage('factura', new File(['<a/>'], 'inv.xml', { type: 'text/xml' }));
      await flush();
      http.expectOne(URL_AI).flush('boom', { status: 500, statusText: 'Server Error' });
      expect(await promise).toBe(false);
      expect(spy).not.toHaveBeenCalled();
      const all = JSON.stringify(service.messages());
      expect(all).not.toContain(btoa('<a/>'));
      expect(service.messages().some(m => m.sender === 'user' && m.text === 'factura')).toBe(false);
      expect(service.isLoading()).toBe(false);
      spy.mockRestore();
    });
  });
});
