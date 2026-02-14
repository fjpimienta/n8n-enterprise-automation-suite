import { InjectionToken } from '@angular/core';
import { ChatConfig } from '../interfaces/chat-config';

export const CHAT_CONFIG_TOKEN = new InjectionToken<ChatConfig>('CHAT_CONFIG_TOKEN');