# 🛠️ Contact & CRM Bridge v2 (n8n Workflow)

## 📝 Descripción
Este workflow implementa un sistema robusto de captura de prospectos y sincronización con CRM utilizando n8n. Diseñado bajo una arquitectura de microservicios, integra validación de identidad externa vía JWT, persistencia inteligente (Upsert) y un sistema de notificaciones automáticas con manejo de excepciones.

El flujo actúa como el backend orquestador para los formularios de contacto de Hosting3m. Su función principal es validar la legitimidad de la petición, procesar la información del cliente y asegurar que los datos lleguen tanto a la base de datos como al equipo de ventas sin duplicidades.

---

## 🚦 Versiones del Workflow

| Versión | Estado | Endpoint Path | Cambios Principales | Archivo JSON |
| :--- | :--- | :--- | :--- | :--- |
| **v1** | `Legacy` | `/contactoHosting3m` | Lanzamiento inicial. | `v1-contact.json` |
| **v2** | `Stable` | `/v2/contact` | CRUD v2, soporte para Roles de Usuario, manejo de errores mejorado y paths amigables. | `v2-contact.json` |

---

### ⚙️ Lógica de Negocio
1. **Seguridad Perimetral:** Validación de tokens mediante un microservicio externo de JWT.
2. **Control de Acceso:** Filtro mediante nodo If que bloquea peticiones no autorizadas (401 Unauthorized).
3. **Normalización:** Extracción y limpieza de campos mediante JavaScript (Nodo Code).
3. **Estrategia Upsert (Inteligente):** 
    * Intento 1: Intenta una inserción directa (POST /insert).
    * Fallback: Si falla (usuario existente), busca el ID del cliente (POST /getone) y realiza una actualización (POST /update).
4. **Confirmación Multicanal:**
    * Correo de agradecimiento al cliente (vía SendMail).
    * Notificación interna detallada al equipo de soporte (vía SendMailContact).

---

## 🛠️ Instalación
- **Requisitos previos:**
    * Instancia de n8n (v2.2.4 o superior).
    * Credenciales SMTP configuradas para los nodos de envío de correo.
    * Un servicio CRUD activo en https://n8n.hosting3m.com/webhook/.../crud/v2/customers.
- **Importación:**
    * Copia el archivo .json de este workflow.
    * En n8n, crea un nuevo flujo y selecciona "Import from File" o pega el código directamente.
- **Configuración de Credenciales:**
    * JWT Auth: Configura tu cuenta de "JWT Auth account" para validar el token de entrada.
    * SMTP: Configura las cuentas n8n@hosting3m.com y contacto@hosting3m.com en los nodos de Email.

---

## 🚀 Uso
    El flujo se activa mediante una solicitud HTTP POST al endpoint contactoHosting3m.

``` Bash
    curl -X POST "https://n8n.hosting3m.com/webhook/contactoHosting3m" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <TU_TOKEN_JWT>" \
  -d '{
    "names": "Francisco",
    "middlename": "Javier",
    "lastname": "Pimienta",
    "email": "fjpimienta@hosting3m.com",
    "phone": "+5219991234567",
    "service": "Cloud Hosting",
    "message": "Hola, solicito información sobre sus servicios."
  }'
```

Ejemplo de Respuesta Exitos:
```
{
  "success": true,
  "mensaje": "El mensaje se ha enviado de forma satisfactoria."
}
```