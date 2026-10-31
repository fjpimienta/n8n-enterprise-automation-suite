import { Injectable, inject, signal } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { map, catchError, of, finalize, firstValueFrom } from 'rxjs';
import { CHAT_CONFIG_TOKEN } from '../tokens/chat.token';
import { ChatConfig } from '../interfaces/chat-config';
import { TenantService } from 'core-auth'; // 🚀 IMPORTANTE: Importamos el servicio de sesión multi-tenant
import { checkAttachment, readAsBase64, resolveAttachmentsConfig } from '../utils/attachment.util';

export interface ChatMessage {
  text: string;
  sender: 'user' | 'bot';
  timestamp: Date;
  /** Metadata only: file content and Base64 never live in the history. */
  file?: { name: string; type: string; size: number; previewUrl?: string };
}

// ⚠️ NOTA: Quitamos providedIn: 'root' para forzar su provisión vía configuración
@Injectable()
export class AiService {
  private http = inject(HttpClient);
  private config = inject(CHAT_CONFIG_TOKEN); // Inyección segura del token
  private tenantService = inject(TenantService); // 🚀 Inyección del contexto del rancho

  private sessionId = 'web-' + crypto.randomUUID();

  // Signals
  messages = signal<ChatMessage[]>([
    { text: `👋 Hola, soy tu ${this.config.title || 'Asistente'}. ¿En qué puedo ayudarte?`, sender: 'bot', timestamp: new Date() }
  ]);
  isLoading = signal<boolean>(false);

  /**
   * Resolves to true when the message was delivered, false when it was refused or failed
   * (the draft and file can then be offered again by the caller).
   */
  sendMessage(query: string, file?: File): Promise<boolean> {
    if (file) return this.sendWithFile(query, file);
    if (!query.trim() || !this.config.apiUrl_ai) return Promise.resolve(false);

    this.updateChat(query, 'user');
    this.isLoading.set(true);

    // 🚀 Extraemos el ID del rancho activo de forma segura
    const currentTenantId = this.tenantService.activeTenant()?.id_company;

    this.http.post<{ output: string }>(this.config.apiUrl_ai, {
      chatInput: query,
      sessionId: this.sessionId,
      tenant_id: currentTenantId // 🚀 ENVIAMOS EL CONTEXTO A N8N
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
    return Promise.resolve(true);
  }

  private async sendWithFile(query: string, file: File): Promise<boolean> {
    const attachments = resolveAttachmentsConfig(this.config.attachments);
    if (!query.trim() || !this.config.apiUrl_ai || !attachments.enabled) return false;

    // Size and type are checked BEFORE reading the file.
    const check = checkAttachment(file, attachments);
    if (!check.ok) {
      this.updateChat('⚠️ No se pudo enviar el archivo adjunto.', 'bot');
      return false;
    }

    const userMessage: ChatMessage = {
      text: query,
      sender: 'user',
      timestamp: new Date(),
      file: { name: check.name, type: check.type, size: check.size }
    };
    this.messages.update(msgs => [...msgs, userMessage]);
    this.isLoading.set(true);

    try {
      const currentTenantId = this.tenantService.activeTenant()?.id_company;
      // The Base64 lives only in this request scope: no signal, history, storage or log.
      const base64 = await readAsBase64(file, attachments.maxBytes);
      const response = await firstValueFrom(this.http.post<{ output: string }>(this.config.apiUrl_ai, {
        chatInput: query,
        sessionId: this.sessionId,
        tenant_id: currentTenantId,
        file: { name: check.name, type: check.type, size: check.size, base64 }
      }));
      this.updateChat(response?.output || '⚠️ Sin respuesta del servidor.', 'bot');
      return true;
    } catch {
      // Deliberately no logging of the error: it must never carry request content.
      this.messages.update(msgs => msgs.filter(m => m !== userMessage));
      this.updateChat('⚠️ Lo siento, no pude enviar el archivo. Tu mensaje y el archivo siguen listos para reintentar.', 'bot');
      return false;
    } finally {
      this.isLoading.set(false);
    }
  }

  private updateChat(text: string, sender: 'user' | 'bot') {
    this.messages.update(msgs => [...msgs, { text, sender, timestamp: new Date() }]);
  }
}