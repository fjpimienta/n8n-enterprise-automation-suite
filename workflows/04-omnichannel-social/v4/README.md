# README for v4/OmniChannel Workflow

## Diagrama de Flujo
```mermaid
flowchart TD
    A[Cron] --> B[SetX]
    B --> C[SaveImage]
    C --> D[UploadImageX]
    D --> E[GetPageTokens]
    E --> F[ExtractPageToken]
    F --> G[PostToFacebookPage]
    F --> H[Post Company]
    F --> I[Post Personal]
    G --> J[Check Publish]
    H --> J
    I --> J
    J --> K[Validar Posts]
    K --> L[Create X]
    L --> M[HTTP Request]
    M --> N[Get Articles]
    N --> O[Genera Token]
    O --> P[Set User]
    P --> Q[Stop and Error]
    Q --> R[Imagen Guardada]
    R --> S[Merge]
    S --> T[Validar Posts]
    T --> U[Generate Image OpenAI1]
    U --> V[Convert Image]
    V --> W[Upload To Server]
    W --> X[Imagen Guardada]
    X --> Y[Create X]
    Y --> Z[PostToFacebookPage]
    Z --> AA[Create X]
    AA --> AB[Post Company]
    AB --> AC[Post Personal]
    AC --> AD[Paso 1: Subir Foto]
    AD --> AE[Paso 2: Publicar]
    AE --> AF[Wait]
    AF --> AG[AI Art Director]
    AG --> AH[OpenAI Chat Model1]
    AH --> AI[Generate Image OpenAI1]
```

## Dependencias
- **Credenciales:**
  - X API 1 (Twitter)
  - Facebook Graph Posts
  - LinkedIn Credential
  - OpenAi account

- **Nodos Externos:**
  - Twitter API
  - Facebook Graph API
  - OpenAI API

## Diccionario de Datos
### Webhook Principal
- **Estructura JSON Esperada:**
```json
{
  "operation": "getAll",
  "fields": {
    "created_at": {
      "_gte": "2023-01-01T00:00:00Z",
      "_lte": "2023-12-31T23:59:59Z"
    }
  }
}
```

### Notas
- Asegúrate de que las credenciales estén configuradas correctamente en n8n.
- Revisa el diagrama de flujo para entender la lógica del workflow.