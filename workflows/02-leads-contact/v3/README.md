# 🛠️ Contact & CRM Bridge v3 (n8n Workflow)
## 📝 Concepto
Frontend Gateway / Centralized Auth / Smart Upsert Strategy

## 📝 Descripción
La versión v3 de este orquestador de contactos perfecciona la integración entre el frontend (formularios web) y el backend (CRM). Se ha reescrito para adherirse al patrón de Seguridad Centralizada, utilizando el sub-flujo de validación de tokens compartido.

Este workflow actúa como un proxy inteligente: recibe los datos del formulario, verifica la identidad del usuario a través del validador corporativo, y gestiona la inserción o actualización de datos en el sistema CRUD, garantizando que el equipo de ventas reciba notificaciones en tiempo real sin duplicidad de registros.

---

## 🚦 Versiones del Workflow

| Versión | Estado | Endpoint Path | Cambios Principales | Archivo JSON |
| :--- | :--- | :--- | :--- | :--- |
| **v1** | `Legacy` | `/contactoHosting3m` | Lanzamiento inicial. | `v1-contact.json` |
| **v2** | `Legacy` | `/v2/contact` | CRUD v2, soporte para Roles de Usuario, manejo de errores mejorado y paths amigables. | `v2-contact.json` |
| **v3** | `Stable` | `/v3/contact` | Auth Reutilizable (Sub-workflow), CORS Headers estrictos y lógica Upsert refinada. | `v3-contact.json` |

---

### ⚙️ Lógica de Negocio
1. **Gateway & CORS:** El webhook de entrada (v3/contact) ahora maneja cabeceras CORS específicas (Access-Control-Allow-Origin: https://hosting3m.com) y expone headers de seguridad (x-jwt-claim-role).
2. **Seguridad Delegada:** En lugar de validar el JWT localmente, invoca al Sub-workflow v3/SW ValidaToken. Si el token es inválido, corta el flujo inmediatamente con un 401 Unauthorized.
3. **Estrategia Upsert (Vía CRUD Proxy):
    * Paso A (Optimista): Intenta insertar el cliente nuevo llamando al microservicio CRUD (POST /insert).
    * Paso B (Corrección): Si el CRUD devuelve un error de llave duplicada, el flujo captura la excepción, busca al cliente existente por email (POST /getone) y actualiza sus datos (POST /update).
4. **Notificaciones Transaccionales:**
    * Cliente: Recibe un correo de confirmación automática (HTML template).
    * Staff: Recibe una alerta con el detalle técnico del requerimiento (Servicio, Mensaje, Teléfono).

---

## 🛠️ Instalación
- **Requisitos previos:**
    * Instancia de n8n (v2.3.6 o superior).
    * Credenciales SMTP configuradas para los nodos de envío de correo.
    * Este flujo REQUIERE tener instalado el workflow v3/SW ValidaToken (ID: RSz6L3aXj3NfumwG) para funcionar.
    * Un workflow CRUD activo en https://n8n.hosting3m.com/webhook/.../crud/v3/customers.
- **Importación:**
    * Importa el archivo v3-contact.json.
    * Verifica que el nodo "Verify Token" apunte correctamente al ID de tu sub-workflow de validación.
  **Configuración de Nodos:**
    * Nodos HTTP (Insert/Update): Asegúrate de que la URL apunte a tu servicio CRUD activo (ej. .../crud/v2/customers o v3).
    * Nodos Email: Revisa que las credenciales SMTP (contacto@hosting3m.com) estén activas.

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

## 🤝 Contribución
### Si deseas mejorar este flujo o añadir validaciones adicionales (como MFA o logging avanzado)::
    1. Haz un Fork del repositorio.
    2. Crea una nueva rama (git checkout -b feature/MejoraSeguridad).
    3. Realiza tus cambios y haz un Commit (git commit -m 'Añadida validación de expiración').
    4. Sube los cambios a tu rama (git push origin feature/MejoraSeguridad).
    5. Abre un Pull Request.

---

## 📄 Licencia
### Este proyecto demuestra la capacidad de integración de n8n con stacks modernos de backend:Este proyecto está bajo la licencia n8n Sustainable Use License. Eres libre de usarlo y modificarlo para fines personales o internos de empresa.


Desarrollado por: Francisco Jesus Pérez Pimienta - Ingeniero en Sistemas Computaciones y Maestro en Administracion de Proyectos.