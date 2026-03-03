# Changelog

All notable changes to the `ui-chat` library will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-02-14
### 🚀 Initial Release
First stable release of the shared communication module for Hosting3M Ecosystem.
Designed to act as a bridge between Angular Frontends and n8n AI Agents.

### ✨ Features
- **Standalone Components:** Full support for Angular Standalone APIs.
- **AI Integration:** Native support for n8n Webhook communication via HTTP.
- **Smart UI:**
    - Chat bubbles with distinct styles for User vs. AI.
    - Markdown rendering support within responses.
    - Auto-scroll logic.
- **Session Management:** Built-in `sessionId` handling (UUID v4).

### 🏗 Architecture
- **Dependency Injection:** Implemented `CHAT_CONFIG_TOKEN` for environment agility.
- **Service Layer:** `AiService` decoupled from root injector to allow per-app configuration.

### 📦 Integration
- Exposed `AiChatComponent` and `AiService` for direct consumption by `dashboard` and `pista-hielo`.

## 📦 Authors

**Francisco Jesus Pérez Pimienta**
*Senior Systems Architect & Project Lead*
Hosting3M Automation Suite

```
---
*Built with the assistance of AI-powered development tools.*

```