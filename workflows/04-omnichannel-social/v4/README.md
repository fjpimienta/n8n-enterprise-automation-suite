# README for v4/OmniChannel Workflow

## Diagrama de Flujo
```mermaid
graph TD
    subgraph Trigger & Setup
        A[Cron] --> B[Set User]
        B --> C[SaveImage]
        C --> D[UploadImageX]
    end
    subgraph "Social Distribution (Parallel)"
        E[GetPageTokens] --> F[ExtractPageToken]
        F -->|Post| G[Post to Facebook]
        F -->|Post| H[Post Company]
        F -->|Post| I[Post Personal]
    end
    subgraph "AI Content Engine"
        J[Check Publish] --> K[Validar Posts]
        K --> L[Create X]
        L --> M[HTTP Request]
        M --> N[Get Articles]
        N --> O[Genera Token]
        O --> P[Generate Image OpenAI1]
        P --> Q[Convert Image]
        Q --> R[Upload To Server]
    end
    subgraph "Final Execution"
        R --> S[Imagen Guardada]
        S --> T[Post Generated Content]
        T --> U[Create X]
        U --> V[Post Company]
        U --> W[Post Personal]
        W --> X[Paso 1: Subir Foto]
        X --> Y[Paso 2: Publicar]
        Y --> Z[Wait]
        Z --> AA[End]
    end
```

## Dependencias
- **Credenciales:**
  - X API 1 (Twitter)
  - Facebook Graph Posts
  - LinkedIn Credential
  - OpenAi account

- **Nodos Externos:**
  - Facebook Graph API
  - OpenAI API

## Diccionario de Datos
### Cron
- **Schedule:** 7:05 AM

### Notas
- Asegúrate de que las credenciales estén configuradas correctamente en n8n.
- Revisa el diagrama de flujo para entender la lógica del workflow.