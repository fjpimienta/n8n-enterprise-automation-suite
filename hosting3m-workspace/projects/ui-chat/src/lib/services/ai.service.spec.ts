import { TestBed } from '@angular/core/testing';
import { AiService } from './ai.service';
import { provideHttpClient } from '@angular/common/http';
import { provideHttpClientTesting } from '@angular/common/http/testing';
import { CHAT_CONFIG_TOKEN } from 'ui-chat/tokens/chat.token';

// 👇 IMPORTA ESTO: Busca dónde está definido CHAT_CONFIG_TOKEN en tu proyecto.
// A veces está en el mismo './ai.service' o en un archivo '../chat.config' o '../tokens'.
// Si VS Code no te lo sugiere, búscalo en 'ai.service.ts'.

describe('AiService', () => {
  let service: AiService;

  beforeEach(() => {
    TestBed.configureTestingModule({
      providers: [
        AiService,
        provideHttpClient(),
        provideHttpClientTesting(),
        // 👇 LA SOLUCIÓN: Inyectamos una configuración falsa para el test
        {
          provide: CHAT_CONFIG_TOKEN,
          useValue: {
            apiUrl: 'http://localhost:test',
            apiKey: 'mock-key',
            model: 'mock-model'
          }
        }
      ]
    });
    service = TestBed.inject(AiService);
  });

  it('should be created', () => {
    expect(service).toBeTruthy();
  });
});