# 🛠️ Contact & CRM Bridge v2 (n8n Workflow)

## 📝 Descripción
Este workflow es la evolución del sistema de captura de leads de Hosting3m. Actúa como un orquestador inteligente que recibe peticiones, valida identidad mediante JWT, normaliza datos y ejecuta una lógica de Upsert (Update or Insert) en el core de la base de datos a través de una API CRUD interna.

---

## 🚦 Versiones del Workflow

| Versión | Estado | Endpoint Path | Cambios Principales | Archivo JSON |
| :--- | :--- | :--- | :--- | :--- |
| **v1** | `Legacy` | `/contactoHosting3m` | Lanzamiento inicial. | `v1-contact.json` |
| **v2** | `Stable` | `/v2/contact` | CRUD v2, soporte para Roles de Usuario, manejo de errores mejorado y paths amigables. | `v2-contact.json` |

---

### ⚙️ Lógica de Negocio
1. **Validación JWT:** El flujo está protegido mediante autenticación JWT, asegurando que solo peticiones autorizadas puedan registrar contactos.
2. **Procesamiento de Campos:** Mediante nodos de Code (JavaScript), se normalizan los encabezados y el cuerpo del mensaje para un manejo limpio de datos.
3. **Inteligencia de Persistencia (Flowchart):** 
    * Intenta registrar al cliente directamente (Insert).
    * Si el cliente ya existe (basado en el email), el flujo captura el error, busca el ID del cliente (getCustomer) y procede a actualizar la información existente (Update).
4. **Confirmación Multicanal:** Envía un correo de confirmación al cliente.
    * Notifica al equipo de ventas/soporte con los detalles del servicio solicitado.

---

## 🛠️ Instalación
- **Requisitos previos:**
    * Instancia de n8n (v2.1.4 o superior).
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