# Contributing to Hosting3M Automation Suite

Gracias por contribuir a esta suite. Este documento cubre cómo levantar el entorno,
el flujo de trabajo esperado, y las reglas no negociables de seguridad y calidad.

Si usas Claude Code, buena parte de esto ya está reforzado en `CLAUDE.md` (raíz) y en
`.claude/settings.json` — este archivo es la versión para humanos.

---

## 1. Antes de empezar

**Requisitos:**
- Node.js 18+ (recomendado vía `nvm`, evita `sudo npm install -g`)
- Docker + Docker Compose (para el stack local de n8n/Postgres/MySQL)
- Angular CLI (`npm install -g @angular/cli`)

**Setup inicial:**
```bash
git clone <repo>
cd n8n-enterprise-automation-suite
npm install
```

El espejo local de la base de datos (`n8n-enterprise-db`) se restaura automáticamente
todos los días desde el VPS vía `~/scripts/backup_postgres_vps_to_local.sh`. **Antes de
proponer cualquier cambio de esquema, valida contra ese clon local** — `schema.sql` y los
seeds versionados en el repo se han desactualizado respecto a producción más de una vez.
No los uses como única fuente de verdad.

---

## 2. Flujo de trabajo

1. Crea una rama desde `main` con un nombre descriptivo: `feat/agro-erp-movement-rules`,
   `fix/dashboard-metacrud-shield`.
2. Trabaja en cambios pequeños y enfocados — un PR, un propósito.
3. Antes de abrir el PR: corre lint y build del/de los proyectos que tocaste
   (`ng build <app> --configuration=production`).
4. Abre el PR contra `main` con una descripción clara de qué cambia y por qué — en inglés
   (ver sección 3).
5. Espera revisión antes de mergear. No hagas `git push --force` sobre ramas compartidas.

---

## 3. Estándar de Commits — Conventional Commits

Todos los commits, en inglés, modo imperativo, con scope del app/lib afectado:

```
<type>(<scope>): <description>
```

**Types:** `feat`, `fix`, `refactor`, `chore`, `docs`, `test`, `perf`

**Ejemplos:**
```
fix(ui-pdf-export): correct finalY offset on multi-page tables
feat(agro-erp): add REEMO movement rule validation
chore(core-auth): bump AUTH_ENV_CONFIG schema version
```

Código, nombres de variables, interfaces TypeScript, comentarios, y descripciones de PR:
**siempre en inglés**, incluso si la discusión en el Issue o PR es en español.

---

## 4. Estilo de código

- **Angular 21:** Standalone Components, Signals (`computed`, no lógica derivada
  duplicada manualmente).
- **TypeScript:** strict mode, sin `any` salvo justificación explícita en comentario.
- **Estado de formularios explícito:** en `hotel-website`, todo formulario expone
  `isSubmitting` / `success` / `error` — no booleans sueltos ad-hoc.
- **Meta-CRUD:** las mutaciones van por el gateway n8n, no por SQL manual ad-hoc.
  Recuerda que los errores llegan como HTTP 200 con `error: true` — nunca confíes solo en
  el status HTTP.

---

## 5. Base de datos y migraciones

- **Nunca** ejecutes `DROP`, `TRUNCATE`, o `DELETE` en cascada contra producción o el VPS.
  Propón siempre un paso de backup/dry-run primero.
- Toda migración nueva debe poder validarse contra el clon local antes de tocar producción.
- Toda query, pipeline, y capa de componente debe filtrar por `id_company`
  (aislamiento multi-tenant fail-closed). Si el tenant no es explícito en el contexto,
  detente y pregunta — no asumas.

---

## 6. Manejo de Secretos y Credenciales

- **Nunca compartas valores reales** de tokens, API keys, contraseñas o secretos
  compartidos (`INTERNAL_SECRET`, `JWT_SECRET`, etc.) en Issues, Pull Requests, chats de
  trabajo, o cualquier canal no cifrado — ni siquiera para "confirmar que coincide". Usa
  `****` o confirma con un sí/no en su lugar.
- **Los secretos van en `.env`, nunca en `docker-compose.yml` ni en ningún archivo
  versionado.** Verifica que `.env` esté en `.gitignore` antes de tu primer commit en
  cualquier servicio nuevo.
- Si un secreto se expone por accidente (commit, chat, log), **trátalo como comprometido
  de inmediato** y avisa para rotarlo en todos los servicios y ambientes donde se use —
  no lo dejes como pendiente de baja prioridad.

---

## 7. Reportar vulnerabilidades de seguridad

Ver `SECURITY.md`. *(Nota: al momento de escribir esto, ese archivo sigue con el
placeholder genérico del template — no lo trates como proceso definitivo hasta que se
actualice.)*

---

## Código de Conducta

Este proyecto sigue el `CODE_OF_CONDUCT.md` (Contributor Covenant). Se espera un trato
respetuoso en todos los espacios del proyecto.