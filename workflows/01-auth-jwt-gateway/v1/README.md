# 🔑 Enterprise JWT Token Generator v2 (n8n Workflow)

## 📝 Descripción

Este componente es un microservicio de autenticación orquestado en **n8n** que actúa como middleware entre una base de datos relacional y un servicio de firma de tokens. Su función principal es validar la identidad de un usuario, recuperar sus privilegios (roles) desde **PostgreSQL** y emitir un JSON Web Token (JWT) mediante un servicio externo.

---

### 🛡 flujo de Seguridad
1.  **Validación de Identidad:** Recibe credenciales y consulta PostgreSQL (`users` table) para verificar existencia y obtener el rol (`public`, `admin`).
2.  **Aislamiento de Servicio:**
    * El flujo **no genera el token**.
    * Delega la firma criptográfica a un contenedor Docker aislado (`jwt-service:4000`) accesible solo a través de la red interna de Docker (Bridge Network).
3.  **Respuesta Estructurada:** Retorna el Token + Rol para consumo del cliente.

### 🐳 Docker Integration
El uso de `http://jwt-service:4000` demuestra el conocimiento de redes de contenedores, evitando exponer el servicio de firma a la internet pública, reduciendo la superficie de ataque.

---

## 🛠️ Instalación

Para desplegar este flujo en tu instancia de n8n, sigue estos pasos:

1.  **Requisitos previos:**
    * Instancia de **n8n** (v2.0.3 o superior).
    * El contenedor `jwt-service` debe estar corriendo en la misma red que n8n escuchando en el puerto `4000`.
    * Contenedor **PostgreSQL** con una tabla `users` (debe contener columnas `email` y `role`).

2.  **Importación del Workflow:**
    * Copia el contenido del archivo `.json` de este repositorio.
    * En tu panel de n8n, selecciona **"Import from File"** o pega el código en el lienzo.
    
3.  **Configuración de Credenciales:**
    * Configura el nodo de **Postgres** con tus credenciales de base de datos (Host, Usuario, Password).
    * Asegúrate de que la red de Docker permita la comunicación con el host `jwt-service`.

4. **Configuración de Variables de Entorno:**
    * Asegúrate de que tu `docker-compose.yml` incluya el servicio de tokens:
      ```bash
        # Comando para levantar la infraestructura necesaria
        docker-compose up -d jwt-service postgres-compose
---

## 🚀 Uso

El flujo se activa mediante una solicitud **HTTP POST**. Una vez procesado, devuelve un objeto JSON con el token generado y el rol del usuario recuperado de la base de datos.

### Ejemplo de Solicitud (cURL):

    ```bash
    curl -X POST [https://tu-instancia-n8n.com/webhook/genera-token-v2](https://tu-instancia-n8n.com/webhook/genera-token-v2) \
      -H "Content-Type: application/json" \
      -d '{
        "user": "francisco.perez@example.com"
      }'

    ###Ejemplo de Respuesta Exitosa:
        JSON
            {
              "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
              "role": "admin"
            }

---

## 🤝 Contribución
###Si deseas mejorar este flujo o añadir validaciones adicionales (como MFA o logging avanzado)::
    1. Haz un Fork del repositorio.
    2. Crea una nueva rama (git checkout -b feature/MejoraSeguridad).
    3. Realiza tus cambios y haz un Commit (git commit -m 'Añadida validación de expiración').
    4. Sube los cambios a tu rama (git push origin feature/MejoraSeguridad).
    5. Abre un Pull Request.

---

## 📄 Licencia
###Este proyecto demuestra la capacidad de integración de n8n con stacks modernos de backend:Este proyecto está bajo la licencia n8n Sustainable Use License. Eres libre de usarlo y modificarlo para fines personales o internos de empresa.


Desarrollado por: Francisco Jesus Pérez Pimienta - Ingeniero en Sistemas Computaciones y Maestro en Administracion de Proyectos.