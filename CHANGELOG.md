# Changelog
Todos los cambios notables en el proyecto **n8n Enterprise Automation Suite** serán documentados en este archivo.

El formato se basa en [Keep a Changelog](https://keepachangelog.com/es-ES/1.0.0/), y este proyecto se adhiere a [Semantic Versioning](https://semver.org/lang/es/).

## [3.0.0] - 2026-01-13
### 🚀 Añadido (New Features)
- **Hotel Management Core:** Implementación completa del ecosistema hotelero.
    - **MCP Server:** Nuevo servidor compatible con Model Context Protocol para consultas de inventario vía IA.
    - **Dashboard SPA:** Cliente web (Angular/Tabler) para gestión visual de reservas y *Room Rack*.
- **Auth Gateway v2:** Microservicio centralizado para la firma y validación de tokens RS256 (JWT).
- **News Intelligence v2:** Integración de generación de imágenes con IA para noticias sin miniatura.

### 🔄 Cambiado (Improvements)
- **Dynamic CRUD Engine:** Refactorización mayor de los subflujos `Build Query` y `Normalize` para soportar transacciones complejas del módulo hotelero.
- **OmniChannel Orchestrator:** Mejora en la lógica de *idempotencia* para evitar duplicidad de posts en X y LinkedIn bajo alta concurrencia.
- **Contact Bridge:** Migración a validación estricta de tipos de datos antes de la persistencia.

### 🔒 Seguridad
- Implementación de rotación de claves en el servicio JWT.
- Hardening de las conexiones Docker entre el Dashboard y n8n.

## [2.0.0] - 2026-01-03
### 🚀 Añadido
- **Arquitectura Modular:** Implementación de sub-workflows reutilizables (`Execute SQL`, `Normalize Data`) para reducir deuda técnica.
- **Sistema de Versionado:** Adopción formal de Semantic Versioning para el control de releases.

### 🔄 Cambiado
- **Refactorización CRUD:** Separación de la lógica de negocio de la capa de acceso a datos. Ahora `Build Query` construye SQL dinámico basado en esquemas JSON.
- **OmniChannel v1.5:** Soporte añadido para la API v2 de Twitter y manejo de límites de caracteres por red social.
- **Contact Flow:** Optimización de tiempos de respuesta del webhook (reducción de latencia de 200ms a 50ms).

## [1.0.0] - 2025-12-20
### 🎉 Lanzamiento Inicial
- Despliegue de la infraestructura base (IaaS) con Docker Compose y redes aisladas.
- Configuración inicial de PostgreSQL con extensión `pgvector`.
- **Core Workflows:**
    1. Generador de Tokens (Auth básico).
    2. Formulario de Contacto (MVP).
    3. Generador de Noticias (Scraper simple).
    4. Social Poster (Unicanal).
    5. Agente IA WhatsApp (V1 sin memoria a largo plazo).

---
*Este changelog es mantenido automáticamente por el equipo de arquitectura.*