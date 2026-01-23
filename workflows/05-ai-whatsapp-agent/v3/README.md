# 🤖 AI Agent WhatsApp v3: Multi-Service Hub & RBAC Dinámico

**Concepto:** Model Context Protocol (MCP) / PostgreSQL Auth / Data Integrity (MÉTACRUD)

La versión 3 eleva el sistema a nivel empresarial. Se abandona la validación estática para integrar una base de datos en tiempo real y se implementa el estándar MCP para conectar la IA con herramientas de gestión hotelera sobre consultas de disponibilidad, huespedes y reservas.

## 📝 Descripción

Este flujo orquestado en n8n gestiona un hotel y una empresa de hosting simultáneamente. La gran evolución de la v3 es su capacidad de realizar operaciones de escritura seguras (Create/Update) mediante herramientas MCP, protegiendo la integridad de los datos con reglas estrictas de validación.

---

## 🚀 Novedades de la V3:
1. **RBAC Dinámico (PostgreSQL):** Ya no se hardcodean los números. El nodo Get User Role consulta una base de datos PostgreSQL para identificar si el usuario es ADMIN o GUEST en milisegundos.
2. **Model Context Protocol (MCP):** Integración con hotel-management mediante clientes MCP, permitiendo a la IA interactuar con sistemas externos de forma estandarizada.
3. **Clasificación de Intenciones Robusta:** Un agente clasificador (AI Agent Type) actúa como router lógico, etiquetando la conversación como HOSTING, HOTEL o NEUTRO.
4. **Pipeline de Audio de Alta Fidelidad:**
    * STT: Whisper para una transcripción precisa.
    * TTS: OpenAI TTS para respuestas de voz naturales.
    * Normalización: Nodo Code para inyección de MIME types (audio/mpeg) asegurando compatibilidad total con WhatsApp.
5. **Arquitectura de Resiliencia:** Implementación de .first() y .last() en expresiones para evitar errores de vinculación de ítems (Paired Item Data) en flujos asíncronos.

---

## ⚙️ Lógica del Workflow
1. **Entrada Multimodal:** Ahora incluye un filtro para rechazar imágenes de forma educada, manteniendo el enfoque en texto y voz.
2. **Filtro de Seguridad Inicial:** Si se detecta una imagen, el flujo se desvía a una respuesta controlada de "No admitido".
3. **Capa de Datos:** Se recupera el perfil del usuario desde la DB. El nodo Set Role consolida el mensaje, el número y el rol.
4. **Capa de Inteligencia:**
    * Switch IA: Dirige el contexto hacia el Agente Senior de Hosting o el Asistente del Hotel.
    * Memoria: Simple Memory con ventana de 50 mensajes, indexada por el número de teléfono del usuario.
5. **Salida Adaptativa:** El nodo If detecta si el origen fue audio para responder con voz, o texto para responder con mensaje escrito.

---

## 🛠️ Stack Tecnológico
* **Orquestador:** n8n (v1.x+ con LangChain Nodes).
* **Modelos de Lenguaje:** GPT-4o-mini (Cerebro), Whisper (STT), OpenAI TTS (Voz).
* **Base de Datos:** PostgreSQL (Gestión de Roles y Usuarios).
* **Protocolos:** MCP (Model Context Protocol) para gestión de habitaciones.
* **Lógica:** JavaScript (Node.js) para manipulación de binarios y limpieza de datos.

---

## ⚙️ Configuración y Despliegue

Para desplegar este workflow en tu infraestructura, sigue estos pasos:
1. **Base de Datos:**
    * Asegúrate de tener una tabla users con las columnas phone, role e is_active.
2. **MCP Server:**
    * El flujo espera un endpoint MCP en https://n8n.hosting3m.com/mcp/hotel-management.
3. **Variables de Entorno:**
    * Configurar credenciales de OpenAI y WhatsApp Business API.
4. **Ajuste de Expresiones:**
    * Para asegurar estabilidad, los nodos finales utilizan: {{ $('WhatsApp Trigger').first().json.messages[0].from }}

---

## 🚀 Uso

El agente funciona de forma reactiva a los mensajes entrantes en la cuenta de WhatsApp vinculada:

* Interacción por Texto: El usuario pregunta por precios de dominios o hosting; el agente responde siguiendo el rol de asesora comercial técnica.

* Interacción por Voz: 1. El cliente envía un audio. 2. El flujo lo descarga, lo transcribe (Whisper) y lo envía al Agente. 3. El Agente genera la respuesta y el nodo GenerateAudio la convierte en una nota de voz para el cliente.

* Gestión de Horarios y Pagos: La IA está programada para dar información textual exacta sobre métodos de pago y horarios de oficina cuando se le solicita.

---

## 🤝 Contribución
### Si deseas mejorar este flujo o añadir validaciones adicionales (como MFA o logging avanzado):
    1. Haz un Fork del repositorio.
    2. Crea una nueva rama (git checkout -b feature/MejoraSeguridad).
    3. Realiza tus cambios y haz un Commit (git commit -m 'Añadida validación de expiración').
    4. Sube los cambios a tu rama (git push origin feature/MejoraSeguridad).
    5. Abre un Pull Request.

---

## 📄 Licencia
### Este proyecto demuestra la capacidad de integración de n8n con stacks modernos de backend:Este proyecto está bajo la licencia n8n Sustainable Use License. Eres libre de usarlo y modificarlo para fines personales o internos de empresa.


Desarrollado por: Francisco Jesus Pérez Pimienta - Ingeniero en Sistemas Computaciones y Maestro en Administracion de Proyectos.