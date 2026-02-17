# WhatsApp Agent Workflow

## Diagrama de Flujo

```mermaid
flowchart TD
    A[WhatsApp Trigger] --> B[Set Message]
    B --> C[Get User Role]
    C --> D{Switch Role}
    D -->|ADMIN| E[AI Agent]
    D -->|GUEST| F[AI Agent Type]
    E --> G[Send Text]
    E --> H[Send Audio]
    F --> I[Send Message]
    H --> J[Convert Audio]
    J --> K[Send Audio]
    C --> L[GetUrlAudio]
    L --> M[Download]
    M --> N[Transcribe]
    N --> O[MessageAudio]
    O --> P[If]
    P -->|true| Q[GenerateAudio]
    P -->|false| R[Send Text]
```

## Dependencias
- **OpenAI API**: Se requiere una cuenta de OpenAI para el modelo de chat.
- **WhatsApp API**: Se necesita una cuenta de WhatsApp para enviar y recibir mensajes.
- **Postgres**: Se utiliza para obtener el rol del usuario basado en su número de teléfono.

## Diccionario de Datos
El Webhook principal espera recibir el siguiente JSON:

```json
{
  "messages": [
    {
      "from": "string",
      "text": {
        "body": "string"
      },
      "audio": {
        "id": "string"
      }
    }
  ],
  "role": "string"
}
```

---

Este README proporciona una visión general del flujo de trabajo del agente de WhatsApp, incluyendo un diagrama de flujo, las dependencias necesarias y el formato de datos esperado.