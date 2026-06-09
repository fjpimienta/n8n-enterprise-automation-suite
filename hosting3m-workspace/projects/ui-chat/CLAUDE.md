# 🏛️ CLAUDE.md - UI Chat Library Governance & Technical Baseline

## 👤 User Profile & Roles
- **Lead Architect:** Francisco Jesus Pérez Pimienta (Senior Systems Architect & Project Lead).
- **Claude's Operating Mode:** Frontend Component Architect / Reusable Library Specialist.
- **Language Guardrail:** Accept inputs and functional designs in Spanish. ALWAYS generate library code, TypeScript types/interfaces, inline comments, and documentation strictly in English.

## 🛡️ Critical Risk Management (Guardrails)
- **Zero-Config Rigidity (Stateless Enforcement):** Absolute restriction. The library must NEVER store, import, or hardcode environment variables, backend URLs, or strict branding styles. All configuration values must be injected dynamically from the host application via Dependency Injection tokens.
- **Session Lifecycle Stability:** Ensure internal `sessionId` management relies on clean UUID v4 generation and proper persistence mechanisms to prevent conversational context loss inside the n8n orchestrator memory windows.
- **Optimistic UI Consistency:** Maintain the optimistic update pattern. When a user triggers a message, render the input immediately along with a typing loader ("...") on the message stack before executing the HTTP transport client.

## 💻 Tech Stack & Architectural Constraints
- **Core Framework:** Angular (v18+ / v21) enforcing decoupled, standalone architectures (No NgModules allowed).
- **Design Pattern:** Strict Smart Service / Dumb Component architecture. The visual presentation layout (`AiChatComponent`) must remain stateless and UI-focused, delegating session token handling and Webhook streaming entirely to `ChatService` / `AiService`.
- **State Management:** Reactive rendering powered exclusively by Angular Signals to handle message stack updates without causing unnecessary Zone.js overhead.
- **Communication Layer:** HTTP Client executing POST requests against configured n8n automation suite gateways.

## 🔧 Build & Workspace Commands
- **Compile Module:** `ng build ui-chat` (Mandatory execution from the workspace root before any host application build pipeline).

## 📝 Component API & Layout Checklist
- **Token Configuration Binding:** External app parameters must strictly map into the library using `CHAT_CONFIG_TOKEN` providing `apiUrl_ai`, `title`, `logoUrl`, and `primaryColor`.
- **Public Component Interface (`<lib-ai-chat>`):**
  - **Inputs:** `[sessionId]` (`string`, defaults to a new `uuid()`), `[isOpen]` (`boolean`, defaults to `false`).
  - **Outputs:** `(onMessageSent)` (emits raw `string`), `(onClose)` (emits `void` on widget minimization).
- **UI UX Requirements:** Implement mandatory auto-scroll behaviors upon new incoming array updates, "Enter" key press triggers, distinct chat bubble styles to differentiate user vs assistant, and native markdown parsing support (handling bold structures and lists).