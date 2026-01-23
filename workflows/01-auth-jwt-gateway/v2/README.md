# 🔑 Enterprise JWT Token Generator v2 (n8n Workflow)

## 📝 Descripción

Este componente es un microservicio de autenticación orquestado en n8n que actúa como middleware de seguridad. Su función principal es recibir una identidad de usuario, comunicarse de forma segura con un servicio interno de firma y retornar un JSON Web Token (JWT) junto con el rol asignado.

Este flujo destaca por su enfoque en seguridad por aislamiento, delegando la lógica criptográfica a un servicio especializado no expuesto a internet.
---

## 🚦 Versiones del Workflow

| Versión | Estado | Endpoint Path | Cambios Principales | Archivo JSON |
| :--- | :--- | :--- | :--- | :--- |
| **v1** | `Legacy` | `/genera-token` | Lanzamiento inicial. | `v1-auth.json` |
| **v2** | `Stable` | `/v2/genera-token` | Integración de Rol y uso de Variables de Entorno. | `v2-auth.json` |

---

## 🏗️ Arquitectura del Flujo

### 🛡 flujo de Seguridad
1.  **Recepción (Webhook):** Escucha peticiones POST en el endpoint /v2/genera-token. Soporta CORS (*) para integración con aplicaciones web front-end.
2.  **Generación de Token (HTTP Request):**
    * Se comunica con el contenedor jwt-service en el puerto 4000.
    * Payload: Envía el nombre de usuario y un INTERNAL_SECRET recuperado de las variables de entorno de n8n ($env["INTERNAL_SECRET"]).
    * Aislamiento de Red: Utiliza resolución DNS interna de Docker, evitando la exposición pública de la llave secreta.
3.  **Respuesta Estructurada (Respond to Webhook):** Retorna un objeto JSON limpio con el token y el role, mapeando dinámicamente el código de estado HTTP según la respuesta del servicio.

### 🐳 Docker Integration
El uso de `http://jwt-service:4000` emuestra el aprovechamiento de redes de contenedores (Bridge Network), lo que garantiza que la firma del token ocurra en un entorno controlado y de baja latencia.

---

## 🛠️ Instalación

Para desplegar este flujo en tu instancia de n8n, sigue estos pasos:

1.  **Requisitos previos:**
    * Instancia de **n8n** (v2.2.4 o superior).
    * El contenedor `jwt-service` debe estar corriendo en la misma red que n8n escuchando en el puerto `4000`.
    * Contenedor **PostgreSQL** con una tabla `users` (debe contener columnas `email` y `role`).

2.  **Importación del Workflow:**
    * Copia el contenido del archivo `.json` de este repositorio.
    * En tu panel de n8n, selecciona **"Import from File"** o pega el código en el lienzo.
    
3.  **Configuración de Credenciales:**
    * Configura el nodo de **Postgres** con tus credenciales de base de datos (Host, Usuario, Password).
    * Asegúrate de que la red de Docker permita la comunicación con el host `jwt-service`.

4. **Configuración de Variables de Entorno:**
    * Asegúrate de que tu docker-compose.yml incluya el secreto:
      ```
      services:
        n8n:
          environment:
            - INTERNAL_SECRET=tu_clave_secreta_super_segura
      ```

      ```bash
        # Comando para levantar la infraestructura necesaria
        docker-compose up -d jwt-service postgres-compose
      ```
---

## 🚀 Uso

El flujo se activa mediante una solicitud **HTTP POST**. Una vez procesado, devuelve un objeto JSON con el token generado y el rol del usuario recuperado de la base de datos.

### Ejemplo de Solicitud (cURL):

    ```bash
    curl -X POST [https://tu-instancia-n8n.com/webhook/v2/genera-token](https://tu-instancia-n8n.com/webhook/v2/genera-token) \
      -H "Content-Type: application/json" \
      -d '{
        "user": "francisco.perez@example.com"
      }'

    ### Ejemplo de Respuesta Exitosa:
        JSON
            {
              "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
              "role": "admin"
            }

---

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