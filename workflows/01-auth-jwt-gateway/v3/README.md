# 🔑 Enterprise JWT Token Generator & Validator v3

## 📝 Descripción

La versión 3 transforma este componente en una Suite de Autenticación Centralizada. Ya no solo genera tokens, sino que introduce un Sub-workflow de Validación (Validator) que actúa como middleware para otros flujos (como el CRUD Engine).

El sistema evoluciona hacia un patrón de Proxy Inverso Seguro: n8n recibe las credenciales y el token, pero delega la lógica criptográfica y la validación de contraseñas enteramente al microservicio interno jwt-service, garantizando que las claves privadas nunca toquen la capa de orquestación.

---

## 🚦 Versiones del Workflow

| Versión | Estado | Endpoint Path | Cambios Principales | Archivo JSON |
| :--- | :--- | :--- | :--- | :--- |
| **v1** | `Legacy` | `/genera-token` | Lanzamiento inicial. | `v1-auth.json` |
| **v2** | `Legacy` | `/v2/genera-token` | Integración de Rol y uso de Variables de Entorno. | `v2-auth.json` |
| **v3** | `Stable` | `/v3/genera-token` | Soporte de Password, Validación Reutilizable (Sub-flow) y manejo de errores 401/403. | `v3_GeneraToken.json, v3_SW ValidaToken.json` |

---

## 🏗️ Arquitectura del Flujo (v3)

### 🛡 flujo de Seguridad
1.  **🏭 Generador de Tokens (Gateway):** 
      * Endpoint: POST /v3/genera-token
      * Cambio Crítico: Ahora requiere user y pass. La autenticación ya no es implícita; n8n hace de pasarela segura hacia el backend.
      * Lógica:
        * Recibe credenciales.
        * Inyecta el INTERNAL_SECRET.
        * Consulta a https://jwt-service:4000/generate-token.

2.  **👮 Verificador de Tokens (Sub-workflow):**
      * Tipo: Execute Workflow Trigger (Uso interno).
      * Función: Este flujo está diseñado para ser llamado por otros workflows (ej. Dynamic CRUD).
      * Lógica:
        * Recibe un { token } desde otro flujo.
        * Consulta a http://jwt-service:4000/verify-token.
        * Devuelve un booleano valid: true/false y el payload decodificado (rol, usuario) al flujo padre.

### 🐳 Docker Integration
El uso de `http://jwt-service:4000` emuestra el aprovechamiento de redes de contenedores (Bridge Network), lo que garantiza que la firma del token ocurra en un entorno controlado y de baja latencia.

---

## 🛠️ Instalación

Para desplegar la suite v3, necesitas importar ambos archivos JSON:

1.  **Requisitos de Infraestructura:**
    * Instancia de **n8n** (v2.3.6 o superior).
    * Microservicio JWT: Contenedor jwt-service corriendo en puerto 4000 (responsable de validar el hash del password contra la DB).
    * Variable de Entorno: INTERNAL_SECRET configurada en n8n.

2.  **Importación del Workflow:**
    * Importa v3_GeneraToken.json (Activa el webhook).
    * Importa v3_SW ValidaToken.json (Este no lleva webhook, se activa por llamada interna).
    
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
    curl -X POST [https://tu-instancia-n8n.com/webhook/v2/genera-token](https://tu-instancia-n8n.com/webhook/v3/genera-token) \
      -H "Content-Type: application/json" \
      -d '{
        "user": "francisco.perez@example.com"
      }'

    ### Ejemplo de Respuesta Exitosa:
        JSON
            {
              "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
              "data": {
                role: "admin"
              }
            }
  ```
 
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