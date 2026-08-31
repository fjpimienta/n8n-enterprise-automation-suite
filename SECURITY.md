# Security Policy — Hosting3M Automation Suite

## Alcance

Esta política cubre el código propio de esta suite: workflows de n8n, los microservicios
en `infrastructure/` (Auth Gateway, Media Server), el monorepo Angular
(`hosting3m-workspace/`), y la configuración de despliegue en este repo.

**Fuera de alcance:** vulnerabilidades en n8n Core, PostgreSQL, o cualquier dependencia de
terceros — repórtalas directamente al proyecto correspondiente. Si una vulnerabilidad de
un tercero afecta específicamente a cómo la usamos aquí (por ejemplo, una configuración
insegura de nuestra parte), sí cae dentro de este alcance.

## Versiones Soportadas

| Componente               | Versión         | Estado                       |
| ------------------------ | --------------- | ----------------------------- |
| n8n Core                 | v2.4.6+          | ✅ Soportado                  |
| Frontend (Angular)       | v1.6.x           | ✅ Soportado                  |
| PostgreSQL / pgvector    | Versionado con n8n Core | ✅ Soportado           |
| Legacy (pre-v2.0.0)      | —                | ❌ Sin soporte, actualizar     |
| Dev / Beta                | Latest          | ⚠️ Experimental, sin garantías |

## Cómo Reportar una Vulnerabilidad

**No abras un Issue público ni un PR para reportar una vulnerabilidad.** Un Issue público
expone el hallazgo a cualquiera antes de que exista un parche.

Repórtala por correo directo a: **fjpimienta@gmail.com**

Incluye, si es posible:
- Componente afectado (workflow de n8n, microservicio, app de Angular, etc.)
- Pasos para reproducir o prueba de concepto
- Impacto estimado (qué datos o funcionalidad se ven comprometidos)

**No incluyas valores reales de secretos, tokens, o credenciales en el reporte** — descríbelos
o redáctalos con `****`; si el hallazgo requiere demostrar acceso, coordina la prueba de
forma privada.

## Qué Esperar

- **Confirmación de recepción:** best-effort, normalmente en menos de 72 horas. Este es un
  proyecto mantenido por una sola persona, no hay SLA corporativo — se atiende lo antes
  posible, pero no hay garantía contractual de tiempo de respuesta.
- **Triage:** se evalúa severidad e impacto real contra producción (multi-tenant,
  exposición de datos de terceros, RCE, etc. se priorizan sobre hallazgos de bajo impacto).
- **Divulgación:** coordinada — se publica detalle técnico del hallazgo (si aplica) solo
  después de que exista un fix desplegado, no antes.
- Si el hallazgo se acepta como vulnerabilidad real, se documenta el fix en `CHANGELOG.md`
  sin necesariamente detallar el vector de explotación públicamente.
- Si se declina (falso positivo, fuera de alcance, riesgo aceptado y documentado), se te
  explica el motivo directamente.

## Historial Relevante

Por transparencia, dos hallazgos reales de este proyecto y su resolución:

- **2026-08-13:** exposición accidental de `INTERNAL_SECRET` en una sesión de trabajo
  (no una vulnerabilidad de código, error operativo). Motivó la sección de manejo de
  secretos en `CONTRIBUTING.md`. Rotación iniciada; confirmación pendiente en ambos
  servicios y ambientes — ver deuda técnica en `CLAUDE.md` raíz.
- **2026-08-15:** path traversal detectado por análisis estático (CodeQL) en el Media
  Server (`upload-file`). Corregido junto con la adición de autenticación JWT/secreto
  interno y rate limiting.
