# UI Chat Shared Library 💬

![Angular](https://img.shields.io/badge/Angular-18%2B-red) ![Pattern](https://img.shields.io/badge/Architecture-Standalone-orange) ![Status](https://img.shields.io/badge/Status-Production%20Ready-green)

## 📖 Executive Summary
**UI Chat** is a reusable, decoupled Angular library designed to integrate AI conversational capabilities into any Hosting3M application. It abstracts the WebSocket/HTTP complexity and provides a standard UI for user interaction.

It is currently the core communication module for:
* **Admin Hotel Dashboard** (Guest Concierge).
* **Pista Hielo Operations** (Support & FAQ).

## ⚡ Key Features
* **Standalone Architecture:** Fully compatible with modern Angular (no NgModules required).
* **Zero-Config Logic:** The library does not hold environment variables. It relies on the consuming app to provide them via DI Tokens.
* **Auto-Reconnect:** Built-in logic to handle network interruptions.
* **Typing Indicators:** Visual feedback when the AI is processing logic in n8n.

## 🛠 Installation & Integration

### 1. Import the Component
In your application's layout or feature component (e.g., `main-layout.component.ts`):

```typescript
import { AiChatComponent } from '@hosting3m/ui-chat';

@Component({
  standalone: true,
  imports: [AiChatComponent], // <--- Import directly
  // ...
})
export class MainLayoutComponent { }

```

### 2. Configuration & Provisioning (Crucial Step) ⚠️

Since the library is stateless, you **MUST** provide both the configuration token and the service in your `app.config.ts` (or `app.module.ts`).

```typescript
import { ApplicationConfig } from '@angular/core';
import { CHAT_CONFIG_TOKEN, ChatConfig, AiService } from '@hosting3m/ui-chat';
import { environment } from '../environments/environment';

const chatConfig: ChatConfig = {
  apiUrl_ai: environment.apiUrl_ai, // Specific URL for this app
  title: 'Hotel Assistant',
  logoUrl: 'assets/logo.png',
  primaryColor: '#003366'
};

export const appConfig: ApplicationConfig = {
  providers: [
    // ... other providers
    
    // 1. Register the Service (Required as it is not provided in root)
    AiService,

    // 2. Provide the Configuration
    {
      provide: CHAT_CONFIG_TOKEN,
      useValue: chatConfig
    }
  ]
};

```

## 🧩 Component API

### `<lib-ai-chat>`

**Inputs:**
| Name | Type | Default | Description |
|------|------|---------|-------------|
| `[sessionId]` | `string` | `uuid()` | Unique identifier for the conversation context (Memory). |
| `[isOpen]` | `boolean` | `false` | Controls the visibility of the chat widget. |

**Outputs:**
| Name | Type | Description |
|------|------|-------------|
| `(onMessageSent)` | `EventEmitter<string>` | Emits when the user sends a message. Useful for analytics. |
| `(onClose)` | `EventEmitter<void>` | Emits when the user minimizes the chat. |

## 🏗 Architecture

The library is structured to enforce separation of concerns:

* **`/tokens`**: Contains `InjectionToken` definitions to avoid circular dependencies.
* **`/services`**: Handles HTTP/WS communication with the n8n Orchestrator.
* **`/components`**: Standalone components responsible for rendering.

## 📦 Authors

**Francisco Jesus Pérez Pimienta**
*Senior Systems Architect & Project Lead*
Hosting3M Automation Suite

```
---
*Built with the assistance of AI-powered development tools.*