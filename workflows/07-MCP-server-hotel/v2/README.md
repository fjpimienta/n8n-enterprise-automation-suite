# 🏨 MCP Server v2: Hotel Management Core

**Concepto:** Backend Microservice / Postgres Tool Abstraction / MCP Server.
Este workflow funciona como un Servidor MCP (Model Context Protocol) dedicado. Su única función es exponer herramientas seguras de consulta de base de datos para que sean consumidas por los Agentes de IA (como el Agente v3 de WhatsApp).

Nota Técnica: Este servidor encapsula la lógica SQL compleja, permitiendo que la IA solicite "ver disponibilidad" sin necesidad de saber escribir código SQL ni conocer la estructura de las tablas.

## 📝 Descripción

El servidor expone 4 herramientas principales que permiten al ecosistema de IA del Hotel San José "ver" el estado real del negocio. Implementa reglas de negocio estrictas directamente en las consultas (por ejemplo, filtrar habitaciones sucias).

---

## 🛡️ Reglas de Negocio Implementadas (SQL):

1. Filtro de Limpieza: Una habitación solo se muestra como disponible si status = 'available' Y su estado de limpieza es 'clean' o 'inspected'. Las habitaciones 'dirty' se ocultan automáticamente de la venta.

2. Búsqueda Insensible (ILIKE): La búsqueda de reservas por nombre ignora mayúsculas/minúsculas para mejorar la experiencia del usuario.

---

## 🛠️ Herramientas Expuestas (Tool Definitions)
El servidor otorga a la IA las siguientes capacidades mediante el nodo MCP Trigger:
1. **Query Rooms:** (Panorama General)
    * Función: Obtiene un resumen agrupado del inventario.
    * Uso: Cuando el cliente pregunta "¿Qué tipos de habitaciones tienen?" o precios generales.
    * Retorno: Lista de Tipos de Habitación, Cantidad Disponible y Precio por Noche.
    * SQL: GROUP BY type, price_night.
2. **Query Available:** (Inventario Detallado):
    * Función: Obtiene el listado crudo de todas las habitaciones listas para vender.
    * Uso: Cuando el sistema necesita asignar un ID de habitación específico para una reserva.
    * Retorno: ID, Número de Habitación, Piso, Amenidades.
3. **Query Available By Room:** (Consulta Específica):
    * Función: Verifica el estado de una habitación puntual (ej. "¿La habitación 10 está libre?").
    * Parámetro Requerido: room_number (String).
    * Lógica: Verifica disponibilidad + limpieza en un solo paso.
4. **Query Reservation By Name:** (Búsqueda de Huésped):
    * Función: Busca reservaciones confirmadas por nombre parcial del huésped.
    * Parámetro Requerido: full_name (String).
    * Uso: Vital para el proceso de Check-in o consultas de estado de reserva.
    * Retorno: ID de reserva, Nombre, Fecha de Check-in y Status.

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