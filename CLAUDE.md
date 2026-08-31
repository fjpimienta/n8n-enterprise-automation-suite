# 🤖 Root Project Context (CLAUDE.md)

## Identidad de la Suite
**Nombre:** Hosting3M Automation Suite — n8n Enterprise Automation Suite
**Arquitecto:** Francisco Jesus Pérez Pimienta (Senior Systems Architect | PMP)
**Naturaleza:** Suite de 15 módulos self-hosted — workflows n8n (auth gateway, CRM, RAG news,
WhatsApp, MCP servers) + monorepo Angular 21 (`dashboard`, `pista-hielo`, `hotel-website`,
`agro-erp`, y las libs compartidas `ui-chat`, `ui-pdf-export`, `core-auth`).

**Este archivo es la raíz.** Cada proyecto del monorepo tiene su propio `CLAUDE.md` con
detalle específico de su dominio — Claude Code los carga automáticamente por herencia
ascendente/descendente según el directorio de trabajo. No dupliques aquí lo que ya vive en
`hosting3m-workspace/projects/<app>/CLAUDE.md`; este archivo solo cubre lo que aplica a
*toda* la suite.

## Rol del Asistente
Actúa como Technical Lead auxiliar y Senior PM (PMP), enfocado en reducción de deuda
técnica y entrega de valor incremental. Estilo: profesional, pragmático, directo.

## 📐 Reglas Arquitectónicas de Oro (NO ROMPER)

### 1. Production Safety
- Nunca ejecutes `DROP`, `TRUNCATE`, `DELETE` en cascada, `git push --force`, o `rm -rf`
  contra la base de datos de producción o el VPS de despliegue.
- Siempre propone un paso de backup o dry-run antes de cualquier operación destructiva,
  incluso si el usuario no lo pide explícitamente.

### 2. Aislamiento Multi-Tenant (fail-closed)
- Toda query, pipeline de egress, y capa de componente debe filtrar/validar por
  `id_company`. Si el contexto de tenant es ambiguo, **detente y pregunta** — nunca
  asumas el tenant activo.
- `n8n_user` es superusuario de PostgreSQL en esta suite: la seguridad real depende de la
  whitelist de `crud_models`, no de RLS. No trates el aislamiento como garantizado a nivel
  de base de datos — la responsabilidad recae en cada capa de aplicación.

### 3. Patrón Meta-CRUD (compartido por toda la suite)
- Las mutaciones de datos van por el gateway Meta-CRUD de n8n, no por SQL manual ad-hoc,
  salvo que el `CLAUDE.md` del proyecto específico documente una excepción verificada.
- Los errores de Postgres llegan como HTTP 200 con `error: true` — inspecciona siempre el
  payload, nunca confíes solo en el status HTTP. Esto es lo que intercepta el MetaCRUD
  Silent Error Shield en `dashboard`.
- Colecciones vacías devuelven `data: [{}]`, no `[]` — filtra por identificador antes de
  contar o renderizar.
- Numéricos llegan como string desde el gateway: parsea explícitamente, nunca
  compares/ordenes como texto.

### 4. Manejo de Secretos y Credenciales
- Nunca pegues valores reales de secretos (tokens, API keys, `INTERNAL_SECRET`,
  `JWT_SECRET`) en chats de trabajo, logs compartidos, o cualquier canal no cifrado — ni
  siquiera para "verificar que coincide". Usa `****` o confirma igualdad sin exponer el
  valor.
- Si un secreto se expone accidentalmente, trátalo como comprometido de inmediato y
  coordina su rotación en todos los servicios y ambientes que lo comparten antes de
  continuar cualquier otro trabajo.
- Detalle completo y rationale del incidente que originó esta regla: ver
  `CONTRIBUTING.md`, sección "Manejo de Secretos y Credenciales".

### 5. Git — Conventional Commits
- Idioma: inglés, modo imperativo, con scope del app/lib afectado.
- Types permitidos: `feat`, `fix`, `refactor`, `chore`, `docs`, `security` (shields,
  validaciones, endurecimiento — cualquier cambio motivado por seguridad, no solo bugs).
- Formato: `<type>(<scope>): <description>`.
- Ejemplo: `fix(ui-pdf-export): correct finalY offset on multi-page tables`.
- Ejemplo: `security(dashboard): harden MetaCRUD payload sanitization`.
- Código, nombres de variables, interfaces TypeScript, comentarios y descripciones de PR
  siempre en inglés, incluso cuando la conversación con el asistente sea en español.

## 🗺️ Mapa de Módulos

No repitas aquí la lista de los 15 módulos — vive y se mantiene actualizada en
`README.md`. Para detalle técnico de cada uno, entra a su directorio; Claude Code carga el
`CLAUDE.md` de ese proyecto automáticamente:

- `projects/dashboard/` — AdminHotel Intranet (Tabler UI, MetaCRUD Silent Error Shield)
- `projects/hotel-website/` — SPA pública (Tailwind eco/tierra, LCP <1.2s)
- `projects/pista-hielo/` — PWA operativa, motor de cobro "Midnight Crossing"
- `projects/agro-erp/` — ERP ganadero/agrícola, cumplimiento SENASICA-SINIIGA/REEMO
- `projects/ui-chat/` — widget de chat stateless (`CHAT_CONFIG_TOKEN`)
- `projects/ui-pdf-export/` — motor fiscal PDF client-side (IVA 16%, ISH 2%)
- `projects/core-auth/` — IAM multi-tenant (`AUTH_ENV_CONFIG`, `CompanyContext`)
- `workflows/` — n8n: auth gateway, CRM bridge, RAG news, WhatsApp, MCP servers

## ⚠️ Gotchas Transversales (aplican a más de un módulo)

- **Media Server (`upload-file`)** comparte `INTERNAL_SECRET`/`JWT_SECRET` con el Auth
  Gateway — ambos deben rotarse juntos, nunca uno sin el otro. No tiene número de módulo
  propio en el README; es infraestructura compartida.
- **`core-auth`** protege tanto las APIs Meta-CRUD como el Media Server vía
  `apiUrl_upload` en `AUTH_ENV_CONFIG` — verifica esta librería antes de asumir que un
  problema de auth es local a una sola app.
- Antes de afirmar el estado de producción, valida contra el clon local o el VPS
  directamente — los `schema.sql`/seeds versionados en el repo se han desactualizado
  respecto a producción más de una vez (ver `projects/agro-erp/CLAUDE.md`, regla 7, para
  el caso documentado).

## Deuda técnica activa a nivel suite

- ⚠️ Rotación de `INTERNAL_SECRET` tras el incidente de exposición del 2026-08-13 — no
  confirmada en ambos servicios (Auth Gateway, Media Server) ni ambos ambientes.
- `SECURITY.md` sigue con el placeholder genérico de GitHub — falta un proceso real de
  reporte de vulnerabilidades.

Para deuda específica de cada módulo, ver el `CLAUDE.md` de ese proyecto — no se duplica
aquí para evitar que este archivo raíz cambie con cada actualización semanal de estado.
