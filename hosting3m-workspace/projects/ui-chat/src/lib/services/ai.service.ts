import { Injectable, inject, signal } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { map, catchError, of, finalize } from 'rxjs';
import { CHAT_CONFIG_TOKEN } from '../tokens/chat.token'; // Asegúrate de la ruta
import { ChatConfig } from '../interfaces/chat-config';

export interface ChatMessage {
  text: string;
  sender: 'user' | 'bot';
  timestamp: Date;
}

// ⚠️ NOTA: Quitamos providedIn: 'root' para forzar su provisión vía configuración
@Injectable()
export class AiService {
  private http = inject(HttpClient);
  private config = inject(CHAT_CONFIG_TOKEN); // Inyección segura del token

  private sessionId = 'web-' + crypto.randomUUID();

  // Signals
  messages = signal<ChatMessage[]>([
    { text: `👋 Hola, soy tu ${this.config.title || 'Asistente'}. ¿En qué puedo ayudarte?`, sender: 'bot', timestamp: new Date() }
  ]);
  isLoading = signal<boolean>(false);

  sendMessage(query: string) {
    if (!query.trim() || !this.config.apiUrl_ai) return;

    this.updateChat(query, 'user');
    this.isLoading.set(true);

    this.http.post<{ output: string }>(this.config.apiUrl_ai, {
      chatInput: query,
      sessionId: this.sessionId
    }).pipe(
      map(response => response?.output || '⚠️ Sin respuesta del servidor.'),
      catchError(err => {
        console.error('Error AI:', err);
        return of('⚠️ Lo siento, tuve un problema de conexión con la base de datos.');
      }),
      finalize(() => this.isLoading.set(false))
    ).subscribe((responseText) => {
      this.updateChat(responseText, 'bot');
    });
  }

  private updateChat(text: string, sender: 'user' | 'bot') {
    this.messages.update(msgs => [...msgs, { text, sender, timestamp: new Date() }]);
  }
}