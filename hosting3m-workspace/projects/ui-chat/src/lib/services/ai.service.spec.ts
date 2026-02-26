import { TestBed } from '@angular/core/testing';
import { AiService } from './ai.service';
import { provideHttpClient } from '@angular/common/http';
import { provideHttpClientTesting } from '@angular/common/http/testing';
import { CHAT_CONFIG_TOKEN } from 'ui-chat/tokens/chat.token';

describe('AiService', () => {
  let service: AiService;

  beforeEach(() => {
    TestBed.configureTestingModule({
      providers: [
        AiService,
        provideHttpClient(),
        provideHttpClientTesting(),
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