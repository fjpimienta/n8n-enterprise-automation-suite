import { Injectable, inject, signal } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { map, catchError, of, finalize } from 'rxjs';
import { environment } from '@env/environment';

export interface ChatMessage {
  text: string;
  sender: 'user' | 'bot';
  timestamp: Date;
}

@Injectable({
  providedIn: 'root'
})
export class AiService {
  private http = inject(HttpClient);
  // URL del webhook de n8n (Ajusta según tu proxy)
  private apiUrl_ai = environment.apiUrl_ai;
  private sessionId = 'web-' + Math.random().toString(36).substring(7);

  // Estado reactivo del chat
  messages = signal<ChatMessage[]>([
    { text: '👋 Hola, soy tu Asistente de Operaciones. ¿En qué puedo ayudarte hoy?', sender: 'bot', timestamp: new Date() }
  ]);

  isLoading = signal<boolean>(false);

  sendMessage(query: string) {
    if (!query.trim()) return;

    // 1. Agregar mensaje del usuario
    this.updateChat(query, 'user');
    this.isLoading.set(true);

    // 2. Llamar a n8n
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
      // 3. Agregar respuesta del bot
      this.updateChat(responseText, 'bot');
    });
  }

  private updateChat(text: string, sender: 'user' | 'bot') {
    this.messages.update(msgs => [...msgs, { text, sender, timestamp: new Date() }]);
  }
}