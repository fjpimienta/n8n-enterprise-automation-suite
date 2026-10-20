# Runbook — Palma Fase 2a: gastos agrícolas (081 + `v6/CRUD` + frontend)

Orden obligatorio: **base de datos → n8n → frontend**. El frontend llega con el merge a `main` (Plesk lo
publica solo), así que **el merge va al final**, cuando 1 y 2 estén verificados. Cada paso se corre en un
comando aparte, revisando la salida antes del siguiente; nunca `apply=true` en el mismo comando que las pruebas.

Pruebas en producción: **solo la empresa 10** ("Plantación de Pruebas"). La empresa 7 es cliente real: nunca se
usa para QA. Nunca pegar tokens ni secretos en el chat; los tokens van a archivos y no se imprimen.

## 0. Preparación (local)

- Rama `feat/agro-erp-palm-expenses-081`. md5 esperados de los archivos de la migración:

  | Archivo | md5 |
  |---|---|
  | `081_agri_expenses.sql` | `cff2ae83599883a1ebd0b474c17a5c46` |
  | `081_tests.sql` | `593deadceb8b43afb39a8180554e7c2f` |
  | `081_rollback.sql` | `7679b7290c4c66b9ff09601951d88f58` |
  | `081_state_check.sql` | `f634ce92ac1e08a0012184bf39cb7e97` |
  | `080_state_check.sql` | `25d5aa29f7407a9db397eb6b56277f2b` |

- Script de huellas: usar el del repo (`node_fingerprints.py`, #831). El de `~/node_fingerprints.py` es una
  versión anterior: `cp node_fingerprints.py ~/node_fingerprints.py`.

## 1. Base de datos: migración 081 (VPS, contenedor `n8n-enterprise-db`, base `hosting3m_db`)

En los comandos, `P` es:

```bash
P='docker exec -i n8n-enterprise-db psql -U n8n_user -d hosting3m_db -v ON_ERROR_STOP=1'
```

1. **Respaldo** (en el VPS):

   ```bash
   docker exec n8n-enterprise-db pg_dump -U n8n_user -Fc hosting3m_db > /root/backups/hosting3m_db_pre081_$(date +%F_%H%M).dump
   ls -lh /root/backups/hosting3m_db_pre081_*.dump   # tamaño razonable, no 0 bytes
   ```

2. **Copiar los archivos** y verificar integridad (todos los `080_*` y `081_*`: `081_tests.sql` usa `\ir`):

   ```bash
   # local
   scp hosting3m-workspace/projects/agro-erp/database/migrations/08[01]_* root@<vps>:/root/m081/
   # VPS
   md5sum /root/m081/081_* /root/m081/080_state_check.sql   # comparar con la tabla del paso 0
   docker exec n8n-enterprise-db rm -rf /tmp/m081 && docker cp /root/m081 n8n-enterprise-db:/tmp/m081
   ```

3. **Revisiones previas (solo lectura)**. Detenerse si alguna falla:

   ```bash
   $P -v expect=applied -f /tmp/m081/080_state_check.sql      # "080 state check (applied): OK"
   $P -v expect=before  -f /tmp/m081/081_state_check.sql      # "081 state check (before): OK"
   $P -c "SELECT id_company, count(*) FROM agri_plantations GROUP BY 1 ORDER BY 1"
   ```

   - Anotar las **5 huellas** de `081_state_check` (`other_crud_models`, `companys_data`, `user_companies_data`,
     `agri_structure_data`, `cattle_expenses_data`): deben repetirse idénticas en 1.5 y 1.7.
   - Plantaciones: se espera **solo la empresa 10**. Si la 7 ya tiene plantación, detenerse: la 081 le sembraría
     las 13 categorías (es la regla acordada, pero confirmarlo antes) y la prueba T03 fallaría.

4. **Dry run** (sin `apply`): esperado `081: company 10 -> 13 categories seeded`, `081: OK` y
   `*** DRY RUN: everything rolled back ***`.

   ```bash
   $P -f /tmp/m081/081_agri_expenses.sql
   ```

5. **Pruebas** (todo se revierte). Esperado `72 | 0 | 72` y `*** 081 tests: everything rolled back ***`.
   Usan la empresa 10, la 3 (de pruebas) y, **solo dentro de la transacción**, la 6 (plantación, categorías y una
   membresía ADMIN temporal que se revierten). Después, repetir el `state_check` `before`: huellas idénticas a 1.3.

   ```bash
   $P -f /tmp/m081/081_tests.sql
   $P -v expect=before -f /tmp/m081/081_state_check.sql
   ```

6. **Aplicar**: esperado `081: company 10 -> 13 categories seeded`, `081: OK`, `*** 081 COMMITTED ***`.

   ```bash
   $P -v apply=true -f /tmp/m081/081_agri_expenses.sql
   ```

7. **Verificar**: `081 state check (applied): OK`, `categories per company with a plantation: 10=13`, huellas
   idénticas a 1.3; y la 080 sigue OK.

   ```bash
   $P -v expect=applied -f /tmp/m081/081_state_check.sql
   $P -v expect=applied -f /tmp/m081/080_state_check.sql
   ```

**Rollback de la base de datos** (sin DROP ni DELETE: desactiva los 7 modelos y el trigger de siembra; tablas y
datos se conservan, inaccesibles por el gateway):

```bash
$P -f /tmp/m081/081_rollback.sql                      # dry run
$P -v apply=true -f /tmp/m081/081_rollback.sql        # aplicar
$P -v expect=rolled_back -f /tmp/m081/081_state_check.sql
```

El respaldo del paso 1.1 (`pg_restore`) es solo último recurso y se decide aparte: revertiría también cualquier
dato capturado después.

## 2. n8n: `v6/CRUD` (`ZhHDs5XoopmqgZvF`) desde el editor de producción

Dos cambios en el nodo `Build Query`, ninguno en otros nodos: las 3 entradas de `spConfigByModel` de la 081 y la
corrección de la detección de fechas del `getall` (un filtro de texto con "T", como `'MONTH'` o `'ACTIVO'`, ya no
se trata como fecha).

1. **Antes.** Descargar `v6/CRUD` del editor de producción y guardarlo como respaldo.
   `python3 -I ~/node_fingerprints.py <export>`; **detenerse si no coincide**:

   ```
   Build Query            856b743c27c3dabb10d2a3b5fcb00b18
   Execute a SQL query    3769295a7cce093d2da9c807a68a6ca6
   Get Model Config       fd354ca78a60e32cd616fc77fac7ba34
   Get Model Name         084730d6cd66211d0703020f1d8f97a9
   Normalize Data         b7741e5edb892a7a6898c731871331eb
   webhook path=crud/v6/:model webhookId=586606bc-e1df-4c02-bf37-10e0a87d4bfd
   postgres nodes=6 credential names=['Postgres account']
   ```

2. **Importar desde el editor** `workflows/06-dynamic-crud-engine/v6/v6-crud.json` sobre el mismo workflow (mismo
   id y `webhookId`). Revisar que el webhook conserva `crud/v6/:model` y que los 6 nodos Postgres usan
   `Postgres account`; **guardar y Publish**.

3. **Después.** Descargar de nuevo y verificar (el `versionId` cambia; lo demás debe coincidir). Si el Build Query
   no es `92fd290c…`, **no está desplegado** (pasó en v1.18.1):

   ```
   Build Query            92fd290c2aa41ce57c24e750def90a0b
   Execute a SQL query    3769295a7cce093d2da9c807a68a6ca6
   Get Model Config       fd354ca78a60e32cd616fc77fac7ba34
   Get Model Name         084730d6cd66211d0703020f1d8f97a9
   Normalize Data         b7741e5edb892a7a6898c731871331eb
   webhook path=crud/v6/:model webhookId=586606bc-e1df-4c02-bf37-10e0a87d4bfd
   postgres nodes=6 credential names=['Postgres account']
   ```

   En LOCAL, justo después de publicar, el webhook respondió 404 unos segundos mientras se registraba: reintentar
   antes de concluir que falló.

4. **Pruebas de API antes del merge** (sin escrituras). Token de ADMIN de la empresa 10 emitido en
   `agroerp.hosting3m.com`, guardado en un archivo y leído sin imprimirlo; header `x-tenant-id: 10` salvo donde se
   indica. URL base: `https://n8n.hosting3m.com/webhook/586606bc-e1df-4c02-bf37-10e0a87d4bfd/crud/v6/<modelo>`.

   | Prueba | Esperado |
   |---|---|
   | `agri_unit_catalog` `getall` sin token | HTTP 401 |
   | `agri_unit_catalog` `getall` | 9 unidades |
   | `agri_expense_categories` `getall` | 13 categorías, todas de la empresa 10 |
   | `agri_expense_balance` `call_sp` sin campos | `success:true`, total 0 (mes en curso) |
   | `agri_expense_summary` `getall` con `grain: 'MONTH'` | sin `error` (antes fallaba con `"MON"`) |
   | `vw_cattle_kpi` `getall` con `current_status: 'ACTIVO'`, `x-tenant-id: 3` | filas, todas `ACTIVO` y de la empresa 3 |
   | `agri_expense_balance` con `x-tenant-id: 7` | HTTP 403, "No perteneces a la empresa seleccionada" |
   | `POST …/webhook/0cce9eb9-5022-433f-a04b-67840e015870/crud/v5/agri_expenses` (sin token) | bloqueado por Cloudflare (403), como cualquier modelo que no es del hotel |

   Revisar `n8n_error_logs`: ninguna fila nueva de `v6/CRUD` en la ventana de prueba, salvo las provocadas a
   propósito.

**Rollback de n8n:** importar desde el editor el export del paso 2.1, publicar y verificar que la huella vuelve a
`856b743c…`. Si el frontend ya está en `main`, revertirlo primero (paso 3): sin estas entradas de
`spConfigByModel`, la pantalla de Gastos falla.

## 3. Frontend: merge a `main` (solo con 1 y 2 verificados)

1. Merge por el flujo habitual (rama → `develop` → `main`). Plesk publica `agroerp.hosting3m.com` desde `main`.
2. Recargar sin caché y confirmar que la empresa 10 muestra **Gastos** en el menú de palma.

**Rollback del frontend:** PR con `git revert -m 1 <merge de main>`; Plesk vuelve a publicar. Los datos capturados
se conservan.

## 4. Pruebas en producción (empresa 10)

1. **EDITOR de pruebas** (con tu OK): crear `qa-editor-palma@example.test` desde **Personal** en la empresa 10, rol
   EDITOR. Es dato de prueba.
2. **ADMIN** (`fjpimienta@gmail.com`), con montos pequeños y descripción `QA despliegue 2a`:
   - Tablero: tarjeta "Gasto del mes" en $0.00.
   - Capturar un gasto general (sin plantación) de `1,000` y uno de PLM-01 → L-01 con cantidad y unidad; el
     monto se muestra formateado y la fecha por defecto es hoy (CDMX).
   - Errores visibles en el modal: monto `10,5`, fecha de mañana, cantidad sin unidad.
   - Balance por mes, semana y día; filtros de plantación, lote y categoría; exportar CSV.
   - Gastos registrados: anular uno con motivo; desaparece del balance y queda marcado como anulado; exportar CSV.
   - Categorías: crear `QA despliegue`, renombrarla y dejarla **inactiva**.
3. **EDITOR**: el menú muestra Gastos y no Plantaciones; la pantalla solo tiene la captura; registrar un gasto y
   ver solo "Gasto registrado"; en Network, ninguna llamada a `agri_expenses`, `agri_expense_summary` ni
   `agri_expense_balance`; `/agricultura/plantaciones` redirige al tablero.
4. **Verificación (solo lectura):**

   ```sql
   SELECT id_company, expense_date, amount, reported_by_email, is_void FROM agri_expenses ORDER BY created_at;
   SELECT id_company, count(*) FROM agri_expense_categories GROUP BY 1;   -- solo la empresa 10
   ```

   Todos los gastos son de la empresa 10; `reported_by_email` es el email de quien inició sesión (el del EDITOR en
   su gasto); ninguna categoría en la 7.
5. **Al final:** anular con motivo `QA despliegue 2a` los gastos de prueba que sigan vigentes (no se borran, por
   diseño); quedan como datos de prueba anulados de la empresa 10.

## 5. Rollback completo (orden inverso)

Frontend (3) → n8n (2) → base de datos (1). Cada parte por separado tiene su procedimiento arriba.

## 6. Después del despliegue

- Asignar versión en el CHANGELOG (`[Unreleased]` → número) y actualizar el `CLAUDE.md` de agro-erp (Regla 18 y
  pendientes de palma).
- Reactivar la restauración diaria de LOCAL: `systemctl --user enable --now pg-backup-restore.timer`, y quitar la
  nota temporal del `CLAUDE.md`. El n8n de LOCAL (`n8n_db_prod_clone`) no se restaura con ella.
