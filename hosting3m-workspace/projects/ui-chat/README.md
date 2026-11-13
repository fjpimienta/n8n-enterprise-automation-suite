# UI Chat Shared Library 💬

![Angular](https://img.shields.io/badge/Angular-18%2B-red) ![Pattern](https://img.shields.io/badge/Architecture-Standalone-orange) ![Status](https://img.shields.io/badge/Status-Production%20Ready-green)

## 📖 Executive Summary
**UI Chat** is a reusable, decoupled Angular library designed to integrate AI conversational capabilities into any Hosting3M application. It provides the chat UI and sends user messages to the configured backend over HTTP.

It is currently the core communication module for:
* **Admin Hotel Dashboard** (Guest Concierge).
* **Hotel Eco-Website** (public Hotel San José assistant).
* **Agro ERP** (cattle/agriculture assistant, including its CFDI XML chat workflow).
* **Pista Hielo Operations** (historical integration; the app is legacy and out of production).

### Attachment status by consumer

* **Agro ERP:** opts in to file attachments for the `CHAT_WEB` CFDI XML intake flow; see the
  details below.
* **Admin Hotel Dashboard:** attachment support is not enabled in its chat configuration.
* **Hotel Eco-Website:** attachment support is not enabled in its chat configuration.
* **Pista Hielo:** historical consumer only; do not infer an active production integration.

## ⚡ Key Features
* **Standalone Architecture:** Fully compatible with modern Angular (no NgModules required).
* **Zero-Config Logic:** The library does not hold environment variables. It relies on the consuming app to provide them via DI Tokens.
* **Error Fallback:** On an HTTP error the service shows a fallback bot message instead of throwing. There is no automatic reconnect or retry; the user resends manually.
* **Typing Indicators:** Visual feedback while `AiService.isLoading()` is true (the AI is processing in n8n).
* **Tenant Context:** Every request carries `tenant_id` taken from `TenantService.activeTenant()?.id_company` (`core-auth`).

## 🛠 Installation & Integration

> **Dependency:** `AiService` injects `TenantService` from `core-auth`. The host application must provide `core-auth` (and `HttpClient`) or the service cannot be created.

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

#### Alternative: `provideUiChat()`

`public-api.ts` also exports `provideUiChat(config: ChatConfig): EnvironmentProviders`, which registers both `CHAT_CONFIG_TOKEN` and `AiService` in one call:

```typescript
import { provideUiChat } from '@hosting3m/ui-chat';

export const appConfig: ApplicationConfig = {
  providers: [provideUiChat(chatConfig)]
};
```

## 📎 Optional File Attachments (disabled by default)

Opt in via `CHAT_CONFIG_TOKEN`. Without `attachments` (or with `enabled: false`) the UI and the HTTP request remain text-only. Enable it only when the host application's backend supports the attachment request contract.

```typescript
const chatConfig: ChatConfig = {
  // ...
  attachments: { enabled: true, maxSizeMb: 5, accept: ['application/pdf', 'text/xml'] }
};
```

| Option | Default | Notes |
|--------|---------|-------|
| `enabled` | `false` | Shows the paperclip. One file per message. |
| `maxSizeMb` | `5` | Can only lower the 5 MB raw hard limit. |
| `accept` | `image/jpeg, image/png, image/webp, application/pdf, text/xml, application/xml` | |

**Type resolution:** `file.type` if it is in `accept`; otherwise, only when it is empty or `application/octet-stream`, the extension is mapped (`.xml`→`text/xml`, `.pdf`, `.jpg/.jpeg`, `.png`, `.webp`) and accepted if the result is in `accept`. The resolved type is what is sent. The file name has control characters stripped and is capped at 255 characters; it is display-only metadata.

### CFDI XML in Agro ERP

The Agro ERP host opts in to attachments through `CHAT_CONFIG_TOKEN` (`attachments.enabled: true`). The component supports selecting **one file per message** with its paperclip button. The file input's `accept` attribute uses the configured MIME types, whose default includes `text/xml` and `application/xml`; `.xml` is mapped to `text/xml` when the browser reports an empty or generic MIME type.

The component currently provides a **file picker only**: drag-and-drop handlers/drop zones are not implemented. It does not parse XML in the browser or render a CFDI-specific preview card. It checks that the file is non-empty and within the configured size limit (at most 5 MB), resolves its MIME type, and shows the selected filename. The consuming app's normal HTTP interceptors apply to the configured `apiUrl_ai` request; UI Chat does not upload the attachment through a separate media endpoint.

When Agro ERP receives the message, its n8n Chat Web workflow validates the XML attachment, sends it to the internal `cfdi-service` for parsing, SAT status lookup and original-file storage, then creates a `CHAT_WEB` draft with `sp_expense_invoice_draft_create`. The parser supports stamped **CFDI 4.0 Ingreso** XML; CFDI 3.3 is not supported by this parser. The assistant presents the resulting draft/preliminary expense information as conversational chat text. The workflow passes parsed concepts to the agent, and `sp_expense_invoice_preview` returns RFC, subtotal, total and other expense details; however, this is not a structured UI contract, and the preview result does not include the invoice UUID or concepts. Do not treat the internal draft ID as the CFDI UUID. The expense is registered only after the user confirms and the workflow calls `sp_expense_invoice_confirm`. This is a conversational preview, not a bespoke UI card.

Source references: Agro ERP's [`app.config.ts`](../agro-erp/src/app/app.config.ts), the versioned [Chat Web workflow](../../../workflows/09-MCP-Agent-Cattle/v6/v6_ai_chat_cattle.json), [MCP workflow](../../../workflows/09-MCP-Agent-Cattle/v6/v6_MCP_Server_Cattle.json), and [`cfdi-service`](../../../microservices/cfdi-service/README.md).

**Request contract:** the same POST as always (`chatInput`, `sessionId`, `tenant_id`) plus, only when a file is attached:

```json
"file": { "name": "invoice.xml", "type": "text/xml", "size": 2931, "base64": "<raw Base64, no data: prefix>" }
```

The Base64 exists only inside the in-flight request: never in the message history (`ChatMessage.file` holds name/type/size only), signals, storage or logs. The size is checked before reading and again against the real byte length. On HTTP error the draft text and the file stay available for retry.

> ⚠️ The client checks are UX only. The backend MUST validate the real file type (content, not the declared type or name), the size, and the caller's tenant membership for `tenant_id`.

## 🧩 Component API

### `<lib-ai-chat>`

`AiChatComponent` currently declares **no `@Input()` or `@Output()`**. Configuration comes only from `CHAT_CONFIG_TOKEN`.

* **Open/closed state:** `isOpen` is an internal signal toggled by the widget itself (`toggleChat()`); the host cannot bind it.
* **Session ID:** generated inside `AiService` as `'web-' + crypto.randomUUID()` when the service is created (private, in memory only). It is not an input and is not persisted, so a new service instance means a new conversation.
* **Events:** no `onMessageSent` / `onClose` outputs exist.
* **Send:** the "Enter" key (`keyup.enter`) and the send button call `send()`; the message list auto-scrolls on updates.

`TODO(verify)`: `CLAUDE.md` still documents `[sessionId]`, `[isOpen]`, `(onMessageSent)` and `(onClose)` as the public interface and markdown rendering of replies; none of these are in the source. Decide whether to implement them or update `CLAUDE.md`.

### `AiService` and `ChatMessage`

`AiService` is exported but not `providedIn: 'root'`. It exposes the `messages` and `isLoading` signals and `sendMessage(query, file?): Promise<boolean>` (resolves `true` when delivered). `ChatMessage` is `{ text, sender: 'user' | 'bot', timestamp, file? }`, where `file` holds metadata only (`name`, `type`, `size`, optional `previewUrl`).

## 🏗 Architecture

The library is structured to enforce separation of concerns:

* **`/tokens`**: Contains `InjectionToken` definitions to avoid circular dependencies.
* **`/interfaces`**: `ChatConfig` and `ChatAttachmentsConfig`.
* **`/services`**: `AiService` handles HTTP POST communication with the n8n Orchestrator (no WebSocket code exists).
* **`/utils`**: `attachment.util.ts` (internal, not exported from `public-api.ts`): size/type checks, file-name sanitizing, Base64 reading.
* **`/components`**: Standalone components responsible for rendering.

## 📦 Authors

**Francisco Jesus Pérez Pimienta**
*Senior Systems Architect & Project Lead*
Hosting3M Automation Suite

```
---
*Built with the assistance of AI-powered development tools.*

```