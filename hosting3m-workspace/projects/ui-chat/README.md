# 💬 UI Chat Library

### 🤖 Angular Reusable AI Chat Interface

## 📝 Descripción
**UI Chat** es una librería de Angular diseñada para integrar asistentes virtuales basados en LLMs (como GPT-4o vía n8n) en cualquier aplicación de la suite Hosting3M. Provee una interfaz moderna, limpia y lista para usar, encapsulando la complejidad de la comunicación HTTP y la gestión de sesiones.

---

## 🚀 Instalación e Integración

Esta librería está diseñada para ser consumida localmente dentro del monorepo.

### 1. Importación en la Aplicación Host (Ej. Dashboard)

En tu `app.config.ts` o módulo principal, provee la configuración del chat:

```typescript
import { provideUiChat } from '@ui-chat'; // Alias configurado en tsconfig

export const appConfig: ApplicationConfig = {
  providers: [
    // ... otros providers
    provideUiChat({
      apiUrl: '[https://n8n.hosting3m.com/webhook/v3/ai/chat](https://n8n.hosting3m.com/webhook/v3/ai/chat)', // Webhook de n8n
      botName: 'San José Concierge',
      primaryColor: '#0d6efd' // Bootstrap Primary
    })
  ]
};

```

### 2. Uso en el Template

Simplemente agrega el selector en tu `app.component.html` o layout principal. El componente maneja su propia posición fija (bottom-right).

```html
<lib-ai-chat></lib-ai-chat>

```

---

## ⚙️ Configuración (Inputs)

El componente `<lib-ai-chat>` acepta los siguientes inputs para personalización rápida:

| Input | Tipo | Default | Descripción |
| --- | --- | --- | --- |
| `isOpen` | `boolean` | `false` | Estado inicial del chat (abierto/cerrado). |
| `placeholder` | `string` | `'Escribe tu duda...'` | Texto de ayuda en el input. |
| `showAvatar` | `boolean` | `true` | Muestra el avatar del bot en los mensajes. |

---

## 🏗️ Stack Tecnológico

* **Framework:** Angular 21
* **Estilos:** SCSS (Scoped) + Bootstrap Utilities
* **Iconos:** SVG Nativos (No requiere dependencias de fuentes externas).

---

## 🔮 Roadmap

* **v0.2:** Soporte para Markdown avanzado (Tablas, Listas, Bloques de código).
* **v0.3:** Soporte para respuestas con "Acciones Sugeridas" (Botones rápidos).
* **v0.4:** Integración de "Feedback Loop" (Thumbs up/down) para entrenar al agente.

---

**Desarrollado por:** Francisco Jesus Pérez Pimienta para Hosting3M Automation Suite.
