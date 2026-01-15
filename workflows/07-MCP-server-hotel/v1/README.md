# 🏨 MCP Server: Hotel Management Core

**Concepto:** Model Context Protocol (MCP) Server para la orquestación de operaciones de hospitalidad en tiempo real.

## 📝 Descripción

Este workflow de n8n actúa como un servidor de herramientas especializado. Expone funciones críticas de la base de datos PostgreSQL de forma segura para que los agentes de IA puedan consultar, reservar y actualizar estados de habitaciones sin intervención humana directa.

---

## 🛠️ Herramientas Expuestas (Capabilities)
El servidor otorga a la IA las siguientes capacidades mediante el nodo MCP Trigger:
1. **Consultar Disponibilidad Real:** Filtra habitaciones que cumplen con el doble criterio: Estado available + Limpieza clean/inspected.
2. **Consulta Todas las Habitaciones:** Permite a la IA tener un mapa completo del inventario para dar alternativas al cliente.
3. **Marcar Habitación Ocupada:** Actualiza los estados de limpieza y ocupación en un solo paso tras una venta.
4. **Registrar Nueva Reserva:** Ejecuta el INSERT en la tabla hotel_bookings, vinculando el ID de la empresa y calculando los montos totales.

---

## 🏗️ Arquitectura de Datos
El servidor interactúa con el esquema de base de datos de Hosting3M, específicamente con:
1. **Tabla hotel_rooms:** Control de inventario, tipo de cama y semáforo de limpieza.
2. **Tabla hotel_bookings:** Registro histórico y activo de transacciones de huéspedes.

---

## 🛡️ Seguridad y Control de Acceso
* **Endpoint:** /hotel-management (Protegido por n8n Webhook Auth).
* **Validación de Escritura:** Aunque el MCP ofrece herramientas de "Update" e "Insert", el flujo principal de WhatsApp (AI Agent Hotel) decide si el usuario tiene el rol ADMIN antes de permitir la ejecución de estas herramientas sensibles.
* **Error Handling:** Conectado a un flujo de manejo de errores específico (9SrVXdATmlrZemJT) para evitar estados inconsistentes en la DB ante fallos de red.

---

## 🚀 Instalación y Despliegue

Para desplegar este workflow en tu infraestructura, sigue estos pasos:
1. **Requisitos:**
    * PostgreSQL con el esquema hotel_management creado.
    * n8n con soporte para nodos PostgresTool (v2.6+).

2. **Configuración:**
    * Importar el JSON del MCP Server.
    * Vincular la credencial Postgres account (ID: BQrod4uGVzM1nvLw).
    * Activar el flujo para habilitar el endpoint del servidor.

---

## 📄 Notas de Operación

**Importante:** La IA utiliza el campo cleaning_status para decidir si ofrece una habitación. Si una habitación está available pero dirty, la herramienta de "Disponibilidad Real" la omitirá automáticamente para proteger la experiencia del huésped.

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