# v4/Contact Workflow

## Diagrama de Flujo
```mermaid
flowchart TD
    A[Webhook Contact] --> B[Set Values]
    B --> C[Validate CloudFlare]
    C -->|Success| D[Insert]
    C -->|Failure| E[Respond Denegate]
    D --> F[Check Insert Success]
    F -->|Success| G[SendMail]
    F -->|Failure| H[Stop on DB Error]
    G --> I[Respond to Webhook]
    E --> J[Respond Denegate]
    H --> K[Respond Denegate]
```

## Dependencias
- **Credenciales:**
  - SMTP para enviar correos electrónicos.
- **Nodos Externos:**
  - Webhook para recibir datos.
  - HTTP Request para interactuar con servicios externos.

## Diccionario de Datos
El Webhook principal espera recibir el siguiente JSON:

```json
{
  "names": "Nombre",
  "middlename": "Segundo Nombre",
  "lastname": "Apellido",
  "email": "correo@ejemplo.com",
  "phone": "1234567890",
  "service": "Servicio solicitado",
  "message": "Mensaje del contacto"
}