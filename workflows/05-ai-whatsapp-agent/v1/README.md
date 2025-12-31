# 💡 AI Agent WhatsApp: Asistente "3M" para Hosting3M

**Concepto:** Microservices Integration / Modular Design

El flujo destaca por su capacidad de memoria contextual (recuerda los últimos 10 mensajes) y su procesamiento multimodal, permitiendo que los clientes se comuniquen tanto por texto como por notas de voz, recibiendo respuestas en el mismo formato.

## 📝 Descripción

Este flujo consiste en un agente de atención al cliente inteligente y multimodal llamado "3M", diseñado para operar de forma autónoma a través de WhatsApp. Su función principal es actuar como asesora experta en servicios de Hosting3M (dominios, hosting, VPS y automatizaciones con IA).

### Lógica del Sistema:
1.  **Omnicanalidad de Entrada:** Procesa mensajes de texto y notas de voz de WhatsApp de forma nativa.
2.  **Procesamiento de Voz (STT/TTS):** 
        * Speech-to-Text: Transcribe audios entrantes usando OpenAI Whisper para que la IA los comprenda.
        * Text-to-Speech: Si el cliente envía un audio, la IA responde con una nota de voz generada artificialmente, manteniendo la coherencia del canal.
3.  **Cerebro de IA (GPT-5.2/OpenAI):** Utiliza modelos de última generación para seguir instrucciones complejas de ventas y soporte.
4.  **Memoria Contextual:** Almacena los últimos 10 mensajes de cada usuario (basado en su número de teléfono) para dar respuestas coherentes.

---

## 🛠️ Instalación

Para desplegar este workflow en tu infraestructura, sigue estos pasos:

1.  **Requisitos de Infraestructura:**
    * Instancia de **n8n v2.0.3** o superior.
    * Cuenta de WhatsApp Business API (a través de Meta for Developers).
    * API Key de OpenAI (con acceso a modelos GPT-4 o GPT-4o y Whisper).
    * Entorno con soporte para manejo de datos binarios (para procesamiento de audio).

2.  **Importación del Workflow:**
    * Copia el contenido del archivo `.json` de este repositorio.
    * En n8n, selecciona "Import from File" o pega el JSON directamente en el lienzo.
    * Nota Técnica: El prompt del sistema en el nodo "AI Agent" requiere una revisión de lógica, ya que mezcla directrices de tecnología con reglas de una tienda de cachorros (legacy code).

3.  **Configuración de Credenciales:**
    * **WhatsApp API:** Configura el AccessToken y el Phone Number ID en los nodos de WhatsApp Trigger y Send.
    * **OpenAI API:** Vincula tu cuenta para los nodos de AI Agent, Transcribe (Whisper) y GenerateAudio (TTS).
    * **Memoria:** El nodo Simple Memory utiliza el número de teléfono del remitente (from) como Session ID para persistir el contexto.

4.  **Despliegue de Servicios Relacionados:**
    ```bash
    # Configuración del Webhook para recibir mensajes de WhatsApp en tiempo real
    docker-compose up -d n8n-ai-worker-service
    # Asegúrate de configurar el endpoint /webhook/9735313a... en el dashboard de Meta
    ```
---

## 🚀 Uso

El agente funciona de forma reactiva a los mensajes entrantes en la cuenta de WhatsApp vinculada:

* Interacción por Texto: El usuario pregunta por precios de dominios o hosting; el agente responde siguiendo el rol de asesora comercial técnica.

* Interacción por Voz: 1. El cliente envía un audio. 2. El flujo lo descarga, lo transcribe (Whisper) y lo envía al Agente. 3. El Agente genera la respuesta y el nodo GenerateAudio la convierte en una nota de voz para el cliente.

* Gestión de Horarios y Pagos: La IA está programada para dar información textual exacta sobre métodos de pago y horarios de oficina cuando se le solicita.

---

### 📦 Tecnologías
Este flujo de trabajo demuestra un dominio avanzado de la integración de sistemas modernos:
    * **n8n Orquestador:** (LangChain Nodes): Orquestador de la lógica del agente y la memoria.
    * **OpenAI GPT-4o:** Cerebro del agente para la toma de decisiones y ventas.
    * **OpenAI Whisper:** Motor de transcripción de voz a texto (STT).
    * **OpenAI TTS:** Motor de generación de voz a partir de texto.
    * **WhatsApp Business API:** Canal de comunicación con el usuario final.
    * **JavaScript:** Nodos de código para limpieza de tipos MIME y manejo de archivos binarios.

---

## 🤝 Contribución
###Si deseas mejorar este flujo o añadir validaciones adicionales (como MFA o logging avanzado):
    1. Haz un Fork del repositorio.
    2. Crea una nueva rama (git checkout -b feature/MejoraSeguridad).
    3. Realiza tus cambios y haz un Commit (git commit -m 'Añadida validación de expiración').
    4. Sube los cambios a tu rama (git push origin feature/MejoraSeguridad).
    5. Abre un Pull Request.

---

## 📄 Licencia
###Este proyecto demuestra la capacidad de integración de n8n con stacks modernos de backend:Este proyecto está bajo la licencia n8n Sustainable Use License. Eres libre de usarlo y modificarlo para fines personales o internos de empresa.


Desarrollado por: Francisco Jesus Pérez Pimienta - Ingeniero en Sistemas Computaciones y Maestro en Administracion de Proyectos.