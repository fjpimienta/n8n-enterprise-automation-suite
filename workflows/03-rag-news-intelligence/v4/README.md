# v4/news Workflow Documentation

## Diagrama de Flujo

```mermaid
flowchart TD
    A[Webhook Noticias] -->|POST| B[Respond to Webhook]
    B --> C{If}
    C -->|success| D[Check Article Exists]
    C -->|failure| E[Respond Denegate]
    D --> F[Validate Article Check]
    F -->|exists| G[Insert]
    F -->|not exists| H[Respond Error Check]
    G --> I[SplitInBatches]
    I --> J[Filter News]
    J --> K[Config Data]
    K --> L[Image Generated]
    L --> M[Respond to Webhook]
    D --> N[RSS Read]
    N --> O[Url Generated]
    O --> P[SplitInBatches]
    P --> Q[Filter News]
    Q --> R[Config Data]
    R --> S[Insert]
    S --> T[Check Article Exists]
    T --> U[Validate Article Check]
    U --> V[Respond to Webhook]
    U --> W[Respond Error Check]
    
    style A fill:#f9f,stroke:#333,stroke-width:4px;
    style B fill:#bbf,stroke:#333,stroke-width:4px;
    style C fill:#bbf,stroke:#333,stroke-width:4px;
    style D fill:#bbf,stroke:#333,stroke-width:4px;
    style E fill:#fbb,stroke:#333,stroke-width:4px;
    style F fill:#bbf,stroke:#333,stroke-width:4px;
    style G fill:#bbf,stroke:#333,stroke-width:4px;
    style H fill:#fbb,stroke:#333,stroke-width:4px;
    style I fill:#bbf,stroke:#333,stroke-width:4px;
    style J fill:#bbf,stroke:#333,stroke-width:4px;
    style K fill:#bbf,stroke:#333,stroke-width:4px;
    style L fill:#bbf,stroke:#333,stroke-width:4px;
    style M fill:#bbf,stroke:#333,stroke-width:4px;
    style N fill:#bbf,stroke:#333,stroke-width:4px;
    style O fill:#bbf,stroke:#333,stroke-width:4px;
    style P fill:#bbf,stroke:#333,stroke-width:4px;
    style Q fill:#bbf,stroke:#333,stroke-width:4px;
    style R fill:#bbf,stroke:#333,stroke-width:4px;
    style S fill:#bbf,stroke:#333,stroke-width:4px;
    style T fill:#bbf,stroke:#333,stroke-width:4px;
    style U fill:#bbf,stroke:#333,stroke-width:4px;
    style V fill:#bbf,stroke:#333,stroke-width:4px;
    style W fill:#fbb,stroke:#333,stroke-width:4px;
```

## Dependencias
- **Credenciales:**
  - `Authorization`: Token para acceder a los recursos.
  - `x-jwt-claim-role`: Rol del usuario para autorización.

- **Nodos Externos:**
  - Webhook para recibir datos.
  - HTTP Request para insertar artículos en la base de datos.

## Diccionario de Datos
El Webhook principal espera recibir un JSON con la siguiente estructura:

```json
{
  "url": "string",
  "title": "string",
  "source": "string",
  "image": "string",
  "published_at": "string"
}
```

- **url:** URL del artículo.
- **title:** Título del artículo.
- **source:** Fuente del artículo.
- **image:** URL de la imagen asociada al artículo.
- **published_at:** Fecha de publicación del artículo en formato ISO 8601.
