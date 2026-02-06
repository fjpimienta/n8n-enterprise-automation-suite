import { Injectable, inject, signal } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { map, catchError, of, finalize } from 'rxjs';
import { CHAT_CONFIG } from 'ui-chat';
// 👇 IMPORTA LA INTERFAZ DESDE SU ARCHIVO ORIGINAL
import { ChatConfig } from '../interfaces/chat-config';

export interface ChatMessage {
  text: string;
  sender: 'user' | 'bot';
  timestamp: Date;
}

@Injectable({ providedIn: 'root' })
export class AiService {
  private http = inject(HttpClient);
  private config = inject(CHAT_CONFIG);

  // 🚫 BORRA la definición de "export interface ChatConfig" que tenías aquí

  private apiUrl_ai = this.config.apiUrl_ai;
  private sessionId = 'web-' + crypto.randomUUID();

  messages = signal<ChatMessage[]>([
    { text: '👋 Hola, soy tu Asistente de Operaciones. ¿En qué puedo ayudarte hoy?', sender: 'bot', timestamp: new Date() }
  ]);

  isLoading = signal<boolean>(false);

  sendMessage(query: string) {
    if (!query.trim() || !this.apiUrl_ai) return;

    this.updateChat(query, 'user');
    this.isLoading.set(true);

    this.http.post<{ output: string }>(this.apiUrl_ai, {
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