import { InjectionToken } from '@angular/core';
import { ChatConfig } from '../interfaces/chat-config'; // Importa la que ya existe

export const CHAT_CONFIG = new InjectionToken<ChatConfig>('CHAT_CONFIG');