# 🤖 Root Project Context (CLAUDE.md)

## Identidad de la Suite
**Nombre:** Hosting3M Automation Suite — n8n Enterprise Automation Suite
**Arquitecto:** Francisco Jesus Pérez Pimienta (Senior Systems Architect | PMP)
**Naturaleza:** Suite de 15 módulos self-hosted — workflows n8n (auth gateway, CRM, RAG news,
WhatsApp, MCP servers) + monorepo Angular 21 (`dashboard`, `pista-hielo` — legacy, fuera de
uso —, `hotel-website`, `agro-erp`, y las libs compartidas `ui-chat`, `ui-pdf-export`, `core-auth`).

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
- `projects/pista-hielo/` — ⚠️ **legacy, fuera de uso** (el proyecto no se llevó a cabo; nada en
  producción depende de él, confirmado por el dueño 2026-10-17). Sus modelos `ph_*` siguen
  registrados y sus datos siguen en la base — ver deuda abajo.
- `projects/agro-erp/` — ERP ganadero/agrícola, cumplimiento SENASICA-SINIIGA/REEMO
- `projects/ui-chat/` — widget de chat stateless (`CHAT_CONFIG_TOKEN`)
- `projects/ui-pdf-export/` — motor fiscal PDF client-side (IVA 16%, ISH 2%)
- `projects/core-auth/` — IAM multi-tenant (`AUTH_ENV_CONFIG`, `CompanyContext`)
- `workflows/` — n8n: auth gateway, CRM bridge, RAG news, WhatsApp, MCP servers

## ⚠️ Gotchas Transversales (aplican a más de un módulo)

- **Media Server (`upload-file`)** comparte `INTERNAL_SECRET`/`JWT_SECRET` con el Auth
  Gateway — ambos deben rotarse juntos, nunca uno sin el otro. No tiene número de módulo
  propio en el README; es infraestructura compartida.
- **Dos gateways Meta-CRUD en producción, con seguridad muy distinta:** `agro-erp` usa
  `crud/v6` (`v6/CRUD`: membresía en `user_companies`, tenant por `tenant_id`/`id_company`,
  identificadores validados). El `dashboard` del hotel y `hotel-website` usan `crud/v5`
  (`v5/CRUD`: rol del JWT, sin membresía, header de tenant opcional y solo `tenant_id`, `update`
  por PK, `insert` como upsert). Desde la contención v1.17.1 (2026-10-17) `v5` solo atiende los
  9 modelos del hotel (nodo `Model Allowlist` + regla WAF de Cloudflare para `crud/v5/`). Nunca
  asumas que un endurecimiento de `v6` protege al hotel; ver deuda abajo.
- **`core-auth`** protege tanto las APIs Meta-CRUD como el Media Server vía
  `apiUrl_upload` en `AUTH_ENV_CONFIG` — verifica esta librería antes de asumir que un
  problema de auth es local a una sola app.
- Antes de afirmar el estado de producción, valida contra el clon local o el VPS
  directamente — los `schema.sql`/seeds versionados en el repo se han desactualizado
  respecto a producción más de una vez (ver `projects/agro-erp/CLAUDE.md`, regla 7, para
  el caso documentado).
- **Imagen de n8n: la única fuente válida en el VPS es `n8n.hosting3m.com/n8n-compose`**
  (`infrastructure/Dockerfile.n8n` y `infrastructure/.env` de esa carpeta construyen y configuran el
  n8n en ejecución; verificado 2026-10-17: `FROM n8nio/n8n:2.29.0`, igual que la capa de la imagen
  en ejecución y que este repo). ⚠️ Deuda: en el VPS hay otras copias del repo con su propio
  `Dockerfile.n8n` (`hotel`, `sanjose`, `admin.pistahielo`, `cattle`, `admin.sanjose`, `agroerp`,
  `n8n-enterprise-new`), algunas con `latest` y otras con 2.23.3; **no construyen nada en ejecución**
  y no deben usarse para reconstruir. Recomendación pendiente: pasar el `FROM` a
  `docker.n8n.io/n8nio/n8n` en la próxima reconstrucción, para evitar el límite de descargas de
  Docker Hub (`429`, ver `projects/agro-erp/CLAUDE.md`, regla 8).
- **Manejo de `password` en el gateway CRUD — invariantes verificadas en vivo (LOCAL,
  `workflow_entity`) en `v5/CRUD` y `v6/CRUD` por igual el 2026-10-05, no solo en la versión
  que usa `agro-erp`:**
  - El nodo `Build Query` omite `password` del `SET` de un `UPDATE` cuando el valor llega
    vacío (`if (key === 'password' && (!value || value === '')) return;`). Esto es carga
    estructural, no un detalle cosmético: los formularios de edición de usuario de
    `agro-erp` y `dashboard` siempre mandan `password: ''` en cada guardado de perfil (el
    campo se limpia al abrir el modal de edición para no mostrar el hash), así que sin este
    guard cualquier edición de perfil (nombre, rol, teléfono) borraría silenciosamente la
    contraseña real del usuario editado. Toda versión futura del motor (`v7`+) debe
    conservar este guard explícitamente — no es un efecto secundario incidental de otra
    lógica, hay que portarlo a mano.
  - Las contraseñas que el gateway escribe se guardan como SHA-256 **sin sal**
    (`crypto.createHash('sha256').update(value).digest('hex')` en `processValue`, mismo
    patrón en `v5` y `v6`). Pendiente: migrar a bcrypt en `jwt-service` al momento del login
    — fuera de alcance de esta nota, solo se documenta el estado actual.
  - **Exposición de `password` (actualizado 2026-10-12):** el export de `v6/CRUD` sincronizado
    desde PRODUCCIÓN el 2026-10-08 (commit d711672) ya trae en `Normalize Data` un filtro
    recursivo que quita `password` de toda respuesta (incluye `RETURNING *` y joins). La nota
    previa (2026-10-05, LOCAL) que decía que ningún nodo filtraba quedó superada. La migración
    073 agrega defensa en profundidad: `users` con columnas explícitas en `Build Query` (el hash
    ya no llega ni a n8n), `SELECT` de `users` solo ADMIN, y la vista `vw_company_members` sin
    `password` para Personal UPP. Sigue pendiente confirmar contra el `workflow_entity` vivo de
    PRODUCCIÓN que ambos nodos coinciden con el repo.
  - **`users` es global (migración 073):** una empresa nunca escribe directo en `users` ni en
    `user_companies`. Altas, cambios de rol y (des)activación van por `sp_access_*`, que impiden
    modificar la cuenta de alguien que también pertenece a otra empresa. El gateway `v6` aplica la
    misma regla al modelo `users` crudo: `insert` sin sobrescribir, `update` solo para miembros
    exclusivos y `delete` bloqueado. ⚠️ **Corrección (2026-10-17):** esto **no** protegía al
    `dashboard` del hotel, que usa `v5/CRUD` (sin estos guardias). Desde v1.17.1 `users` está
    bloqueado en `v5` y la pantalla de usuarios del hotel queda sin servicio hasta migrarlo a `v6`.

## 🚀 Despliegue (aplica a toda la suite)

- **`main` despliega solo los frontends:** Plesk publica desde `main` (agro-erp y también los sitios del hotel).
  Un PR que dependa de base de datos o de n8n **no llega a `main` hasta tener listo su runbook**: orden de
  despliegue, huellas antes/después, pruebas en producción con empresas de pruebas y rollback. Si el frontend no
  depende del cambio, el runbook lo dice explícitamente (p. ej. v1.18.1).
- **Workflows en n8n 2.x:** `n8n import:workflow` **desactiva** lo que importa y `--activeState=fromJson` solo
  funciona en modo queue/multi-main; además cambia el `versionId`. En producción, reemplazar el contenido desde el
  editor de n8n (mismo id y `webhookId`) y publicar.
- **Runbook estándar de un workflow:** (1) descargar el export de producción y sacar su huella
  (`python3 -I ~/node_fingerprints.py <archivo>`; detenerse si no coincide con la huella "antes" esperada);
  (2) importar desde el editor, revisar webhook y credenciales, guardar y **Publish**; (3) **descargar de nuevo y
  verificar con la huella "después" antes de dar el workflow por desplegado** — el editor puede dejar una versión
  guardada sin publicar (pasó en v1.18.1, 2026-10-17: la primera importación no se publicó y solo la huella lo
  detectó); (4) solo entonces, pruebas. Rollback: reimportar el export del paso 1 y publicar.
- **Una consulta parametrizada de n8n se prueba ejecutando el nodo con datos reales, no solo con SQL preparado.**
  El nodo Postgres pasa un `queryReplacement` de tipo arreglo con sus tipos de JS y pg-promise arma la consulta del
  lado del cliente (un número entra sin comillas); uno de tipo texto se parte por comas y descarta los vacíos. Un
  `PREPARE`/`SELECT` suelto no ve nada de eso: v1.17.2 pasó esa validación y falló en producción con un
  `execution.id` numérico (2026-10-17, corregido en v1.18.2). Probar en LOCAL con valores numéricos, vacíos,
  nulos y con comas, y forzar texto en las dos capas (`$n::text` y `String(...)`) cuando el tipo no sea seguro.

## Deuda técnica activa a nivel suite

- ⚠️ Rotación de `INTERNAL_SECRET` tras el incidente de exposición del 2026-08-13 — no
  confirmada en ambos servicios (Auth Gateway, Media Server) ni ambos ambientes.
- 🔴 **Migrar el hotel (`dashboard`, `hotel-website`) de `v5/CRUD` a `v6/CRUD`.** La contención
  v1.17.1 (2026-10-17) cerró en `v5` la inyección SQL (nombre de modelo en `Get Model Config`,
  `sort_by`, campo de `getone`), el registro automático de tablas en `crud_models` y el acceso a
  modelos ajenos al hotel, pero **no** su aislamiento: dentro de los 9 modelos permitidos, cualquier
  JWT válido lee y escribe filas de cualquier empresa (header de tenant opcional, `update` por PK,
  `insert` como upsert). Prioridad por datos personales: `hotel_guests` (nombre, teléfono, correo,
  **fotos de INE**) → `users` → resto (`hotel_bookings`, `hotel_reviews`, `hotel_expenses`, …).
  - La **pantalla de usuarios del `dashboard` queda sin servicio a propósito** (`users` bloqueado
    en `v5`) hasta esta migración.
  - En `v5`, `Security Validation` va directo a `Build Query`, sin `If Error`: un rechazo de
    permisos solo "funciona" porque la ejecución termina en error. Los rechazos que lanza
    `Build Query` responden **HTTP 200 con cuerpo vacío**, no `error:true`.
- ⚠️ **Errores de producción a un tema público de ntfy.sh — MITIGADO en producción el 2026-10-17,
  corrección completa pendiente (v1.18.2).** v1.17.2 (`fix/error-handler-alerts`, #809) se desplegó el
  2026-10-17 y **se revirtió el mismo día**: al probarla, el `INSERT` falló con `invalid input syntax for type
  integer: ""` (un `execution.id` numérico entraba sin comillas) y, como el nodo SQL corría antes que la alerta,
  tampoco salía la alerta. Producción quedó con la versión de la mañana (URL literal, alerta sin texto del error,
  SQL `1f72bc10…`); `NTFY_ALERT_URL` ya está en el `.env`. v1.18.2 corrige ambos puntos. El Global Error Handler
  (`9SrVXdATmlrZemJT`, `errorWorkflow` de `v5` y `v6`, entre otros; **activo** en producción) publicaba
  en el tema público `https://ntfy.sh/alertas_n8n_hosting3m` (ya retirado) el workflow, el nodo, el
  **texto crudo del error** y el link de la ejecución; cualquiera que conociera el tema podía
  suscribirse, y un error de Postgres puede traer valores (p. ej. `Key (email)=(…) already exists`).
  - **Mitigación aplicada a mano en producción (2026-10-17, dueño del proyecto):** tema nuevo, aleatorio
    y no adivinable (el nombre no se comparte ni se versiona), y la alerta ya no incluye
    `error_message`: solo workflow, nodo y link. Sigue siendo un tema sin token: quien conozca el
    nombre puede leerlo.
  - **Pendiente (v1.18.2):** desplegar el handler con la URL fuera del JSON (`$env.NTFY_ALERT_URL`) y el
    `INSERT INTO n8n_error_logs` parametrizado (en producción todavía interpola y escapa solo comillas simples;
    además truena si falta `failed_node`/`error_message`).
  - **Riesgo residual aceptado (decisión del dueño, 2026-10-17):** el tema no tiene token; quien conozca el
    nombre puede leerlo. Propuesta no implementada: tema protegido con token de acceso (credencial Bearer de n8n).
  - Nota: en n8n 2.x un workflow de errores **inactivo no se ejecuta** ("is not active and cannot be
    executed"); en LOCAL está inactivo.
- ⚠️ **`dashboard` y `hotel-website` apuntan a producción incluso en dev** (`environment.ts` con
  `https://n8n.hosting3m.com/...crud/v5`, `v3/genera-token`): correr el hotel en local lee y
  escribe la base de producción. `pista-hielo` igual (legacy).
- ⚠️ **`pista-hielo` legacy con datos en la base:** siguen registrados 8 modelos (`ph_clients`,
  `ph_instructores`, `ph_inventory`, `inventory`, `transactions`, `services`, `payments`,
  `closures`; ya bloqueados en `v5`, todavía alcanzables por `v6` con membresía) y hay datos
  personales (conteos LOCAL 2026-10-17: `ph_clients` 7 — 2 con `tutor_name`, posibles menores —,
  `ph_instructores` 5, `ph_inventory` 12, `ph_transactions` 20). Propuesta (PR aparte): desactivar
  los 8 modelos (`allowed_ops = '{}'`, roles `'NONE'`, patrón 073) y un script de anonimización con
  respaldo previo. **La decisión de retención (conservar, anonimizar o eliminar) es del dueño.**
- ⚠️ **Modelos con datos personales sin consumidor:** `livestock_producers_pii` (CURP/RFC
  descifrados), `livestock_producers` y `employee_credentials` (`nombre`, `curp`, `email`; deja a
  **EDITOR** leer CURP). En `v6` filtran por empresa (verificado 2026-10-17); en `v5` ya están
  bloqueados. Propuesta (PR aparte): desactivarlos con `allowed_ops = '{}'`.
- **Ruta pública de `companys`:** el `If` de `v5`/`v6` salta `Verify Token` para `companys getall`.
  Desde v1.17.1 solo devuelve `id_company`/`company_name`. Ya no tiene consumidor (era el login de
  `pista-hielo`; los logins de `agro-erp` y del hotel reciben la lista solo de `jwt-service` vía
  `v3`/`v4/GeneraToken`, verificado 2026-10-17). Propuesta (PR aparte): quitarla en `v6` para que
  `companys getall` exija token y membresía como cualquier modelo.
- `SECURITY.md` sigue con el placeholder genérico de GitHub — falta un proceso real de
  reporte de vulnerabilidades.
- ⚠️ **`N8N_BLOCK_ENV_ACCESS_IN_NODE=false`:** cualquier workflow (y quien pueda editarlos) lee con
  `$env` las variables de entorno del contenedor de n8n, incluidos `INTERNAL_SECRET`, `JWT_SECRET`,
  las claves de OpenAI y la contraseña de la base. **No se cambia por ahora:** `GenerateToken` (`v3`/`v4`)
  lee `INTERNAL_SECRET` con `$env`, y el Global Error Handler lee `NTFY_ALERT_URL` igual. Endurecerlo
  exige pasar esos valores a credenciales de n8n antes de bloquear el acceso. Sin verificar todavía el
  efecto real de `N8N_BLOCK_ENV_VARS_INCLUDE=INTERNAL_SECRET` (presente en `docker-compose.yml`).

Para deuda específica de cada módulo, ver el `CLAUDE.md` de ese proyecto — no se duplica
aquí para evitar que este archivo raíz cambie con cada actualización semanal de estado.
