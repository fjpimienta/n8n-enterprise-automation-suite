# 🤖 AI Agent WhatsApp v2: Multi-Service Hub (Hosting & Hotel)

**Concepto:** Multi-Agent Orchestration / Intent-Based Routing / Security RBAC

La versión 2 evoluciona de un asistente único a un Hub de Servicios Inteligente. Ahora, el sistema no solo procesa voz y texto, sino que clasifica la intención del usuario para derivarlo a dos unidades de negocio distintas: Hosting3M (Tecnología) y Hotel San José (Hospitalidad), incluyendo un sistema de permisos basado en roles.

## 📝 Descripción

Este ecosistema de agentes utiliza n8n como orquestador central para gestionar comunicaciones multimodales. El flujo identifica quién escribe, qué necesita y qué nivel de acceso tiene antes de responder.

---

## 🚀 Novedades de la V2:
1. Enrutamiento por Intención (Intent Classification): Un agente especializado analiza el mensaje y decide si la consulta es para el área de Hosting, Hotel o si es un saludo Neutro.
2. Control de Acceso basado en Roles (RBAC): Nodo de JavaScript que identifica números administradores.
    * ADMIN: Acceso total a reportes y datos sensibles.
    * GUEST: Acceso limitado a información pública y ventas.
3. Arquitectura Multi-Agente:
    * Agente 3M (Hosting): Arquitecta senior para soluciones técnicas.
    * Agente Hotel: Asistente cálido para gestión de reservas y check-out.
    * Agente Welcome: Filtro inicial para derivación de tráfico.
4. Memoria Expandida: Ventana de contexto aumentada a 50 mensajes para conversaciones de larga duración.
5. Gestión de Medios Mejorada: Ahora incluye un filtro para rechazar imágenes de forma educada, manteniendo el enfoque en texto y voz.

---

## ⚙️ Lógica del Workflow
El Flujo de Decisión:
    * Entrada: WhatsApp (Audio/Texto/Imagen).
    * Procesamiento: * Si es Audio, pasa por Whisper para transcripción.
    * Si es Imagen, se activa el flujo de rechazo controlado.
    * Identificación: El sistema asigna el Rol (Admin/Guest) según el número de origen.
    * Clasificación: El AI Agent Type actúa como router devolviendo solo las etiquetas HOSTING, HOTEL o NEUTRO.
    * Respuesta: El Switch IA activa el agente correspondiente con su propio System Prompt y reglas de estilo.

---

## 🛡️ Reglas de Estilo del Sistema
    * Formato: Uso estricto de asterisco simple (*) para énfasis (evitando el doble asterisco nativo de WhatsApp).
    * Personalidad: Tono ejecutivo para Hosting y tono hospitalario para el Hotel.
    * Seguridad: Bloqueo de información interna para usuarios con rol GUEST.

---

## 🛠️ Instalación

Para desplegar este workflow en tu infraestructura, sigue estos pasos:
1.  **Requisitos de Infraestructura:**
    * Instancia de **n8n v2.3.2** o superior (Uso de nuevos nodos de IA y Switch v3)..
    * Credenciales de OpenAI con acceso a gpt-4o-mini (optimizado para velocidad y costo).
    * API de WhatsApp Business configurada.

2.  **Configuración de Seguridad:**
    * Edita el nodo Code in JavaScript e introduce los números de teléfono autorizados en el array admins.

3.  **Importación:**
    * Importa el nuevo JSON v2
    * Verifica las conexiones de los nodos de memoria y modelos de lenguaje (ahora divididos por especialidad).


---

## 🚀 Uso

El agente funciona de forma reactiva a los mensajes entrantes en la cuenta de WhatsApp vinculada:

* Interacción por Texto: El usuario pregunta por precios de dominios o hosting; el agente responde siguiendo el rol de asesora comercial técnica.

* Interacción por Voz: 1. El cliente envía un audio. 2. El flujo lo descarga, lo transcribe (Whisper) y lo envía al Agente. 3. El Agente genera la respuesta y el nodo GenerateAudio la convierte en una nota de voz para el cliente.

* Gestión de Horarios y Pagos: La IA está programada para dar información textual exacta sobre métodos de pago y horarios de oficina cuando se le solicita.

---

### 📦 Stack Tecnológico (v2)
Este flujo de trabajo demuestra un dominio avanzado de la integración de sistemas modernos:
    * Orquestador: n8n (LangChain Nodes).
    * Modelos de Lenguaje: * gpt-4o-mini (Cerebro principal y clasificadores).
    * Whisper (STT) & OpenAI TTS (Voz).
    * Base de Datos de Sesión: Window Buffer Memory (Session ID basado en número de teléfono).
    * Lógica: JavaScript personalizado para validación de seguridad y formateo de binarios.

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