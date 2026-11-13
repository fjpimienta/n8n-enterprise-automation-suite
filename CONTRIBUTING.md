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
todos los días desde el VPS vía `~/scripts/backup_postgres_vps_to_local.sh` (no deja una base limpia de forma fiable: puede conservar objetos que el volcado no contiene; inferido de tres observaciones del 2026-10-28, no es un comportamiento documentado de la herramienta; para una base limpia ver `workflows/09-MCP-Agent-Cattle/v6/repro-phase5/rehearsal/README.md`). **Antes de
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

### Merge strategy

- For feature, fix, docs, and chore work, use `develop` as the branch base and pull request
  target; this supersedes the generic `main`-based flow in steps 1 and 4 above.
- Feature, fix, docs, and chore branches are based on `develop`, opened as pull requests
  into `develop`, and merged with a squash merge (`gh pr merge N --squash`).
- Releases from `develop` to `main` use a merge commit
  (`gh pr merge N --merge`); never squash a release. Squashing makes `main` and `develop`
  diverge and causes conflicts in the next release.
- If `main` and `develop` have diverged, open a pull request from a branch that merges
  `origin/main` into `origin/develop` before the next release. Merge it with a merge
  commit and no content changes.

### Despliegue de producción

- Tras mergear a `main`, el despliegue de los frontends en Plesk se inicia manualmente con
  "Deploy now". El backend (compose, n8n y base de datos) se despliega manualmente en el VPS
  con su runbook.
- `deploy.sh` despliega solo los servicios indicados: ejecuta `./deploy.sh [--yes] <service>...`.
  Confirma antes del despliegue, etiqueta las imágenes actuales para rollback e imprime los
  comandos de rollback.
- Si un PR depende de migraciones, cambios de Meta-CRUD o workflows n8n, no se mergea a
  `main` hasta que exista un runbook ejecutable con orden de despliegue, comprobaciones,
  pruebas y rollback. Desplegar primero el frontend puede dejar la aplicación apuntando a
  backend/esquema aún no disponible.
- Todo runbook que toque base de datos o n8n debe comenzar con este aviso:

  > ⛔ **NO MERGEAR A `main` HASTA COMPLETAR LAS PARTES 1 Y 2** (base de datos y n8n,
  verificadas con sus huellas). `main` se despliega manualmente por Plesk con git:
  si el frontend se despliega antes, la pantalla nueva puede fallar en producción.

- Para cada operación destructiva o irreversible contra datos/servicios, exige backup o
  dry-run aprobado antes de ejecutarla. Nunca ejecutes `DROP`, `TRUNCATE`, borrados en
  cascada, `rm -rf` contra producción/VPS ni `git push --force`.
- Para publicar un workflow, compara primero el export y la huella de producción con el
  estado esperado; si difieren, incorpora primero las diferencias manuales al repositorio.
  Edita/publica en n8n conservando el workflow y webhook existentes, vuelve a descargar y
  verifica la huella posterior antes de probar. `n8n import:workflow` puede desactivar el
  workflow y no es el procedimiento de producción documentado.
- Ejecuta las pruebas de integración en LOCAL con datos representativos, incluidos
  parámetros numéricos, vacíos, nulos y con comas cuando aplique. La preparación de SQL o
  un `PREPARE` aislado no sustituye ejecutar el nodo real de n8n.
- Los runbooks de frontend deben dejar claro si el cambio no requiere despliegue de DB/n8n;
  el frontend es la última parte cuando existe dependencia de backend.

El runbook de workflows y los detalles operativos versionados están en `CLAUDE.md`
(sección "Despliegue").

## Continuous integration

- Checks run on pull requests targeting `develop` and `main`, and on pushes to `main`.
- GitHub Actions runs ShellCheck and the stubbed `deploy.sh` tests, v5 CRUD tests,
  CFDI service tests, and workspace builds for `ui-pdf-export`, `dashboard`,
  `hotel-website`, and `agro-erp` (`npx ng build agro-erp`); the Agent workflow
  consistency job runs the reproduction prompt checker.
- The `agro-erp` job runs unit tests with `npm test -- agro-erp --watch=false` on Node 22.
- The `dashboard`, `hotel-website`, and `agro-erp` jobs generate placeholder environment
  files at runtime because the real environment files are git-ignored; missing real
  environment files are not a cause of CI failure.
- Every pull request should have all CI checks green before merging. CI does not deploy
  anything.

## Dependency updates (Dependabot)

- Dependabot monitors `hosting3m-workspace`, `workflows/06-dynamic-crud-engine/v5/tests`,
  `microservices/cfdi-service`, `microservices/jwt-service`, `infrastructure/upload-file/app`,
  Dockerfiles in `infrastructure/upload-file` and `microservices/jwt-service`, and GitHub
  Actions in the repository root. Checks run weekly on Mondays; pull requests target `develop`.
- Check that CI is green, then merge the pull request with `--squash`.
- If Dependabot does not rebase a pull request, run `gh pr update-branch <N>` to bring
  `develop` into the branch and re-trigger CI.
- `gh pr view --comments` fails with a Projects (classic) deprecation error. Use
  `gh pr view <N> --json comments,mergeStateStatus -q '{mergeStateStatus, comments: [.comments[].body]}'`
  instead.
- Review the Angular package group on its own. Major updates are not auto-merged and are
  handled manually.
- Before releasing an `apexcharts` major bump, visually check the four Agro ERP livestock
  dashboards.
- CI does not test `upload-file` or `jwt-service`. After merging a Dependabot pull request
  that touches either service, redeploy only that service with `./deploy.sh <service>` and
  run a smoke test: check its health endpoint or make one request.

---

## 3. Estándar de Commits — Conventional Commits

Todos los commits, en inglés, modo imperativo, con scope del app/lib afectado:

```
<type>(<scope>): <description>
```

**Types permitidos:** `feat`, `fix`, `refactor`, `chore`, `docs`, `security`

`security` se usa para cambios motivados por endurecimiento, validaciones o controles de
seguridad. Usa un scope del proyecto o servicio afectado. Esta lista coincide con la
política raíz de `CLAUDE.md`; no agregues types alternativos por convención local.

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

- **Nunca** ejecutes `DROP`, `TRUNCATE`, `DELETE` en cascada ni `rm -rf` contra producción
  o el VPS. Propón y completa un paso de backup/dry-run primero.
- Toda migración nueva debe poder validarse contra el clon local antes de tocar producción.
- Toda query, pipeline, y capa de componente debe filtrar por `id_company`
  (aislamiento multi-tenant fail-closed). Si el tenant no es explícito en el contexto,
  detente y pregunta — no asumas.
- Los gateways CRUD de Agro ERP y del hotel se documentan por separado; consulta la
  documentación específica de cada proyecto para sus integraciones.

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

Sigue el proceso de reporte privado documentado en [`SECURITY.md`](./SECURITY.md). No abras
un issue o PR público para divulgar una vulnerabilidad.

---

## Código de Conducta

Este proyecto sigue el `CODE_OF_CONDUCT.md` (Contributor Covenant). Se espera un trato
respetuoso en todos los espacios del proyecto.