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
* **Tenant Context:** Every request carries `tenant_id` taken from `TenantService.activeTenant()?.id_company` (`core-auth`), read at `ai.service.ts:44`. There is no guard: if no tenant is active, `tenant_id` is left out of the body (JSON drops `undefined`) and the request is still sent (`ai.service.ts:46-49`). See "Documented but not implemented (#1038)".

## 🛠 Installation & Integration

> **Dependency:** `AiService` injects `TenantService` from `core-auth` (`ai.service.ts:6`, `:22`). `TenantService` is `providedIn: 'root'` (`core-auth/src/lib/services/tenant.service.ts:11`), so the host needs `core-auth` installed and `HttpClient` provided; `AiService` itself must be provided explicitly (see step 2).

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

`TODO(verify)`: the workflow and `cfdi-service` behavior below lives in other modules and was not re-checked in this UI Chat docs pass (only the linked workflow file's existence was confirmed). When Agro ERP receives the message, its n8n Chat Web workflow validates the XML attachment, sends it to the internal `cfdi-service` for parsing, SAT status lookup and original-file storage, then creates a `CHAT_WEB` draft with `sp_expense_invoice_draft_create`. The parser supports stamped **CFDI 4.0 Ingreso** XML; CFDI 3.3 is not supported by this parser. The assistant presents the resulting draft/preliminary expense information as conversational chat text. The workflow passes parsed concepts to the agent, and `sp_expense_invoice_preview` returns RFC, subtotal, total and other expense details; however, this is not a structured UI contract, and the preview result does not include the invoice UUID or concepts. Do not treat the internal draft ID as the CFDI UUID. The expense is registered only after the user confirms and the workflow calls `sp_expense_invoice_confirm`. This is a conversational preview, not a bespoke UI card.

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
* **Send:** the "Enter" key (`keyup.enter`, `ai-chat.component.html:70`) and the send button call `send()` (`ai-chat.component.ts:45`); the message list auto-scrolls on updates (`ai-chat.component.ts:35-38`).
* **Loader:** while `isLoading()` is true the widget shows "Escribiendo" followed by three animated dots (`ai-chat.component.html:36-40`).
* **Attachments:** see "Optional File Attachments" above. The paperclip and file input only exist when `attachments.enabled` is true (`ai-chat.component.html:45`, `:63`).

Items documented in earlier revisions that do not exist in the source (`[sessionId]`, `[isOpen]`, `(onMessageSent)`, `(onClose)`, markdown rendering, `ChatService`, streaming) are listed in "Documented but not implemented (#1038)" at the end of this file.

### `AiService` and `ChatMessage`

`AiService` is exported and not `providedIn: 'root'` (`ai.service.ts:17-18`). It exposes the `messages` and `isLoading` signals (`ai.service.ts:27-30`) and `sendMessage(query, file?): Promise<boolean>` (`ai.service.ts:36`). Its resolved value means different things by path:

* **Text message:** resolves `true` as soon as the HTTP request is dispatched (`ai.service.ts:60`), before the answer arrives. It resolves `false` only when the query is blank or `apiUrl_ai` is empty (`:38`). HTTP failures are not reported through the return value; they are shown as a bot message (`:52-55`).
* **Message with file:** resolves `true` only after the response is received and shown (`:93-94`), and `false` on validation failure (`:65-72`) or HTTP failure (`:95-99`), so the caller can keep the draft and file for a retry.

`ChatMessage` is `{ text, sender: 'user' | 'bot', timestamp, file? }` (`ai.service.ts:9-15`), where `file` holds metadata only (`name`, `type`, `size`, optional `previewUrl`).

### Errors and states (as implemented)

* **Text, HTTP error:** the user message stays and a Spanish bot message is added (`ai.service.ts:52-55`). No retry, no toast.
* **Text, empty server response:** a Spanish fallback bot message replaces it (`ai.service.ts:51`).
* **Text, `apiUrl_ai` empty:** `sendMessage` returns `false` without any message, and the component clears the draft anyway (`ai-chat.component.ts:48-49`), so the typed text is lost.
* **Concurrent sends:** `sendMessage` has no `isLoading` check (`ai.service.ts:36-60`) and Enter is not disabled while loading (`ai-chat.component.html:70`). A second message can be sent while the first is pending. `finalize` sets `isLoading` to `false` when the first request ends, even if another is still pending (`ai.service.ts:56`). Documented here as observed behavior; not a decision.
* **File, validation failure:** a Spanish bot message is added and the draft is kept (`ai.service.ts:70`); the component shows the reason inline (`ai-chat.component.ts:70-78`).

`TODO(verify)`: the concurrent-send behavior above was read from the code, not exercised in a browser.

## 🏗 Architecture

The library is structured to enforce separation of concerns:

* **`/tokens`**: Contains `InjectionToken` definitions to avoid circular dependencies.
* **`/interfaces`**: `ChatConfig` and `ChatAttachmentsConfig`.
* **`/services`**: `AiService` handles HTTP POST communication with the n8n Orchestrator (no WebSocket code exists).
* **`/utils`**: `attachment.util.ts` (internal, not exported from `public-api.ts`): size/type checks, file-name sanitizing, Base64 reading.
* **`/components`**: Standalone components responsible for rendering.

## Documented but not implemented (#1038)

Behavior that earlier docs (`CLAUDE.md`, `INFRASTRUCTURE.md`) described but the source does not have. Each line gives what was documented, what exists, and where to look. Tracked in issue #1038; the code is intentionally unchanged. Possible future plan, not decided.

* **`[sessionId]` input** (`CLAUDE.md`, Public Component Interface): documented as a settable input defaulting to `uuid()`. Actual: no `input()`/`@Input()` (`ai-chat.component.ts:15-20`); the id is a private `AiService` field, `'web-' + crypto.randomUUID()` (`ai.service.ts:24`).
* **`[isOpen]` input** (`CLAUDE.md`): documented as a settable input defaulting to `false`. Actual: internal `isOpen = signal(false)` (`ai-chat.component.ts:19`), flipped only by `toggleChat()` (`:41-43`).
* **`(onMessageSent)` output** (`CLAUDE.md`): documented as emitting the message text. Actual: no `output()`/`@Output()`/`EventEmitter` in `src/lib`; `sendMessage` (`ai.service.ts:36`) emits nothing.
* **`(onClose)` output** (`CLAUDE.md`): documented as emitting on minimize. Actual: not implemented; `toggleChat()` (`ai-chat.component.ts:41-43`) only changes the internal signal.
* **Markdown rendering of replies** (`CLAUDE.md`, UI UX Requirements; `INFRASTRUCTURE.md`, Rendering): documented as bold and list rendering. Actual: plain text interpolation `{{ msg.text }}` (`ai-chat.component.html:25`); no markdown parser, no `innerHTML`, no `DomSanitizer` in `src/lib`. If implemented, model output must be sanitized (issue #1038 acceptance criterion).
* **`ChatService`** (`CLAUDE.md`, Tech Stack; `INFRASTRUCTURE.md`, Componentes Clave): documented as the owner of session and webhook logic. Actual: only `AiService` exists (`ai.service.ts:19`).
* **Webhook streaming** (`CLAUDE.md`, Tech Stack): documented as streaming from n8n. Actual: one `http.post` per message that resolves with the full `output` (`ai.service.ts:46-59`, `:87-93`); no streaming code.
* **Signals-only state** (`CLAUDE.md`, State Management; `INFRASTRUCTURE.md`, Reactive State): documented as signals exclusively. Actual: `userInput` (`ai-chat.component.ts:20`) and `destroyed` (`:30`) are plain fields; the draft uses `[(ngModel)]` (`ai-chat.component.html:69`).
* **Stateless component** (`CLAUDE.md`, Design Pattern): documented as holding no draft or file state. Actual: the component holds `userInput`, `selectedFile`, `previewUrl`, `attachmentError` (`ai-chat.component.ts:20-29`) and creates object URLs (`:113`).
* **Session persistence** (`CLAUDE.md`, Session Lifecycle Stability): documented as requiring "proper persistence mechanisms". Actual: none; `src/lib` has no `localStorage`/`sessionStorage`, so a new `AiService` instance starts a new conversation (`ai.service.ts:24`).
* **Tenant guard before sending** (root `CLAUDE.md` §2, fail-closed; referenced by `CLAUDE.md`, Communication Layer): documented as refusing to send without tenant. Actual: no check; the request is sent with `tenant_id` omitted (`ai.service.ts:44`, `:46-49`, `:84`, `:87-91`).
* **English-only code and i18n of user-facing text** (`CLAUDE.md`, Language Guardrail): documented as English. Actual: Spanish comments at `ai.service.ts:6`, `:17`, `:21-22`, `:43`; Spanish user messages at `ai.service.ts:54`, `:70`, `:98` and `ai-chat.component.ts:73-75`.
* **`primaryColor` applied to the widget** (`CLAUDE.md`, Token Configuration; `INFRASTRUCTURE.md`, Configurable Injection): documented as styling the widget. Actual: declared in `chat-config.ts:14` and never read in `src/lib`; the stylesheet uses `var(--primary-color, #206bc4)` (`ai-chat.component.css:171`), and nothing in `src/lib` sets that variable.

## 📦 Authors

**Francisco Jesus Pérez Pimienta**
*Senior Systems Architect & Project Lead*
Hosting3M Automation Suite

```
---
*Built with the assistance of AI-powered development tools.*

```