# Changelog - UI Chat Library
Todos los cambios notables en la librería **ui-chat** serán documentados en este archivo.

## [0.3.0] - 2026-02-09
### 🚀 Lanzamiento Inicial (MVP)
- **Core Chat Widget:** Implementación del componente flotante de chat con diseño responsivo.
    - Soporte para mensajes de usuario (derecha) y asistente (izquierda).
    - Animación de entrada y salida del widget.
    - Indicador visual de carga ("Typing indicator").
- **Integration Layer:**
    - Servicio HTTP optimizado para comunicarse con webhooks de n8n.
    - Manejo automático de `sessionId` para persistencia de contexto en conversaciones largas.
- **Configuración:**
    - Implementación de `CHAT_CONFIG` token para inyectar la URL del backend dinámicamente desde la aplicación consumidora.

### 🐛 Fixes
- **Auto-scroll:** Solucionado el problema donde el chat no bajaba automáticamente al recibir una respuesta larga del bot.
- **Mobile View:** Ajuste de z-index para evitar que el chat quede detrás de elementos de navegación en móviles.

---

*Este changelog es mantenido automáticamente por el equipo de arquitectura.*