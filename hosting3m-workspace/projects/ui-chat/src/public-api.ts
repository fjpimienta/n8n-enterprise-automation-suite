/*
 * Public API Surface of ui-chat
 */
import { EnvironmentProviders, makeEnvironmentProviders } from '@angular/core';
import { ChatConfig } from './lib/interfaces/chat-config';
import { CHAT_CONFIG_TOKEN } from './lib/tokens/chat.token';
import { AiService } from './lib/services/ai.service';

// Exportamos los artefactos necesarios
export * from './lib/components/ai-chat/ai-chat.component';
export * from './lib/services/ai.service';
export * from './lib/interfaces/chat-config';
export * from './lib/tokens/chat.token';

/**
 * Función Proveedora Standalone (Best Practice Moderno)
 * Permite configurar la librería en el app.config.ts sin NgModules
 */
export function provideUiChat(config: ChatConfig): EnvironmentProviders {
  return makeEnvironmentProviders([
    {
      provide: CHAT_CONFIG_TOKEN,
      useValue: config
    },
    AiService // Proveemos el servicio aquí, ligado a esta configuración
  ]);
}