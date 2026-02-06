# Changelog
Todos los cambios notables en el proyecto **n8n Enterprise Automation Suite** serán documentados en este archivo.

El formato se basa en [Keep a Changelog](https://keepachangelog.com/es-ES/1.0.0/), y este proyecto se adhiere a [Semantic Versioning](https://semver.org/lang/es/).

## [3.0.0] - 2026-02-03
### 🚀 Añadido (New Features)
-   **Frontend Ecosystem (Angular 21):** Integración oficial de dos clientes SPA/PWA construidos con la última tecnología de Angular (Signals, Standalone Components).
-   **Hotel Quality Module:** Sistema de rondines de inspección con formularios dinámicos y persistencia **JSONB** en PostgreSQL (Persistencia Híbrida).
-   **PistaHielo Billing Engine:** Nuevo motor de cobro de alta precisión con soporte para turnos nocturnos (**Midnight Crossing Logic**) y reportes de Corte Z.
-   **Mobile UX:** Implementación de diseños "Fat-Finger" y Grid Navigation para operabilidad táctil en tablets.

### 🔄 Cambiado (Improvements)
-   **n8n Protocol Standardization:** Todos los clientes Angular ahora envían datos encapsulados en la propiedad `fields` para compatibilidad nativa con los scripts del Dynamic CRUD Engine.
-   **Infrastructure:** Configuración de Proxy Reverso en entornos de desarrollo para gestión transparente de CORS.
-   **Refactorización UI:** Migración a componentes reactivos (Signals) en ambos dashboards, eliminando dependencias de `ngOnInit` para cálculos de precios.

## [2.1.0] - 2026-01-13
### 🚀 Añadido
-   **Hotel Management Core:** Implementación inicial del servidor MCP y Dashboard SPA básico.
-   **Auth Gateway v2:** Microservicio centralizado para firma y validación de tokens RS256.
-   **News Intelligence v2:** Generación de imágenes con IA para noticias curadas.

### 🔄 Cambiado
-   **Dynamic CRUD Engine:** Refactorización mayor de `Build Query` y `Normalize` para soportar transacciones complejas.
-   **Contact Bridge:** Migración a validación estricta de tipos de datos.

## [2.0.0] - 2026-01-03
### 🚀 Añadido
-   **Arquitectura Modular:** Sub-workflows reutilizables (`Execute SQL`, `Normalize Data`).
-   **Sistema de Versionado:** Adopción formal de Semantic Versioning.

### 🔄 Cambiado
-   **Refactorización CRUD:** Separación de lógica de negocio y capa de acceso a datos.
-   **OmniChannel v1.5:** Soporte API v2 Twitter y manejo de límites de caracteres.

## [1.0.0] - 2025-12-20
### 🎉 Lanzamiento Inicial
-   Despliegue de infraestructura IaaS, Docker Compose y Redes Aisladas.
-   Configuración inicial de PostgreSQL con extensión `pgvector`.
-   **Core Workflows:**
    1. Generador de Tokens (Auth).
    2. Formulario de Contacto (MVP).
    3. News Curator & Social Poster.
    4. Agente IA WhatsApp (V1).

---
*Este changelog es mantenido automáticamente por el equipo de arquitectura.*

