> ⛔ **NO MERGEAR A `main` HASTA COMPLETAR LAS PARTES 1 Y 2** (base de datos y n8n, verificadas con sus huellas).
> `main` se despliega manualmente: el dueño entra a Plesk y despliega con git. Este PR no cambia el frontend, pero el estado del repositorio no debe
> divergir del de producción.

> ⚠️ **ESTADO: probado en una base local descartable (scratch_100, PostgreSQL 15.4); NO aplicado en producción; la importación del
> workflow en n8n está pendiente.** Los resultados de las pruebas y del ciclo local están en «Resultados de la ejecución». Producción no
> se ha tocado (solo una consulta de lectura sobre los roles de `cattle_livestock`): antes de aplicar, haz el respaldo, el estado «before» y el dry run (Parte 1).

# Runbook 103 — modelo del gateway para el alta de ganado del panel (PR 2 de 6)

## Alcance

* **Gateway (`workflows/06-dynamic-crud-engine/v6/v6-crud.json`):** solo el nodo `Build Query`, solo una entrada nueva en
  `spConfigByModel`: `sp_register_livestock_panel` (`tenantPosition: 0`, `actorEmailField: 'actor_email'`, 18 argumentos en el orden de
  la firma de la 102). Las demás entradas y el resto del código del nodo no cambian.
* **Base de datos (103):** UNA fila nueva en `crud_models` (`register_livestock_panel` → `sp_register_livestock_panel`). Solo datos; no se
  cambia la 102 ni ninguna función de la 099/100.
* **Fuera de alcance:** frontend, servicio Angular y pantalla (PR 3-5). **Mientras el frontend no llame al modelo, ninguna ventana
  intermedia cambia lo que ven los usuarios:** nadie envía todavía esa petición.

## La fila de `crud_models`

Sigue el patrón de los modelos `call_sp` de la 081 (`agri_record_expense`, `agri_void_expense`):

| Columna | Valor | Por qué |
|---|---|---|
| `model_name` / `table_name` | `register_livestock_panel` / `sp_register_livestock_panel` | `table_name` es la clave de `spConfigByModel` |
| `allowed_ops` | `{INSERT}` | el gateway valida `call_sp` como INSERT (`Security Validation`) |
| `allowed_roles_insert` | `ADMIN,EDITOR` | **no se agrega OWNER**: el insert directo de `cattle_livestock` no lo permite hoy y no se amplían privilegios |
| `allowed_roles_select/update/delete` | `NONE` | |
| `is_global` / `sp_requires_tenant` | `false` / `true` | el gateway exige `x-tenant-id` con membresía activa y la función lo valida otra vez |
| `allowed_fields` | los 18 argumentos (incluye `confirmed`, `preview_hash`, `force_duplicate`, `actor_email`); sin `id`, `tenant_id` ni `id_company` | |
| `schema_json`, `hooks`, `joins`, `default_filter` | `{}`, `{"pre":[],"post":[]}`, `[]`, `NULL` | sin campos requeridos: la función responde `need_info` |

⚠️ **Consecuencia de no agregar OWNER:** el gateway toma el rol de la membresía de la empresa activa (`Get Membresia` →
`Extract Auth Context`). La función de la 102 sí admite OWNER, pero un usuario con rol OWNER recibirá `403` del gateway (`Security Validation`).
Si el dueño quiere que OWNER use la pantalla, es un cambio de `allowed_roles_insert` decidido aparte (y primero en el insert directo).
`103_state_check.sql` imprime el `allowed_roles_insert` actual del modelo directo `cattle_livestock` para comparar. **Verificado en producción
(solo lectura): es `ADMIN,EDITOR`**, igual que el de esta fila, así que no se amplían privilegios. Se vuelve a ver en la salida del paso 2.

## Verificaciones hechas con el código (sin ejecutar n8n ni SQL)

Nodos de `v6-crud.json` (los números son líneas del código de cada nodo; el JSON guarda cada nodo en una sola línea):

* **`Build Query` (`call_sp`, líneas 371-481 del nodo):** la entrada se busca por `config.table_name`; el correo del actor se sobrescribe
  con el del JWT (`fields[actorEmailField] = config.user_email`, línea 464; si el JWT no trae correo, lanza error); los campos ausentes
  viajan `null` (`fields[p] ?? null`, línea 468); con `sp_requires_tenant` el tenant se exige (línea 473) y se inserta en la posición 0
  como número (`parseInt`, línea 474). SQL: `SELECT sp_register_livestock_panel($1, …, $19) AS resultado;`.
* **`Security Validation` (líneas 51-91):** `call_sp` se valida como `insert`: `allowed_ops` debe incluirlo (líneas 59-64), `allowed_roles_insert`
  no puede estar vacío (69-79) y el rol debe estar en la lista (81-91). Rol = el de la membresía en la empresa del header
  (`Extract Auth Context`), no el del JWT.
* **`Get Membresia` / `Existe Membresia`:** sin membresía activa en `x-tenant-id` responde `Respond Tenant Forbidden` antes de leer el modelo.
* **`Schema Validate` (líneas 7-26):** copia la configuración del modelo. Su chequeo de requeridos en `insert`/`update` no tiene efecto (**Known deviation (#1054)**: el `return` de error queda dentro del `forEach` y no llega a `If Error`); los requeridos no se aplican hoy. `call_sp` no entra, y `schema_json` es `{}`.
* **Filtro de campos:** `allowed_fields` solo se usa en `Build Query` para inyectar `tenant_id`/`id_company` (líneas 18-22) y en las ramas
  `insert`/`update`/`getall` (líneas 82, 146, 224), **no** en `call_sp`. Por eso `confirmed`, `preview_hash` y `force_duplicate` no se
  eliminan (la prueba de Node lo comprueba).
* **`Normalize Data` (línea 79 `case 'call_sp'`):** devuelve `rows[0].resultado` (el `jsonb` de la función) en `data`; quita solo la clave
  `password`. Un error de Postgres llega con `error: true` (líneas 7-16).
* ⚠️ Recordatorio del contrato Meta-CRUD (CLAUDE.md raíz): el gateway responde HTTP 200; el servicio del panel (PR 3) debe leer `error` y
  `data.status`, no solo el código HTTP.
* **Tipos:** el tenant va como número JS y el nodo Postgres lo inserta sin comillas (como `integer`); los demás valores, como texto. La
  firma de la 102 es `(integer, text × 18)`. Lo confirma la prueba real del paso 10 (no solo SQL preparado).

## Orden de despliegue

1. **Base de datos:** la 102 en producción (su runbook: `102_RUNBOOK.md`, con respaldo y dry run). Verifica `102_state_check.sql -v expect=applied`.
2. **Base de datos:** la 103 (esta fila). Pasos de la Parte 1.
3. **n8n:** importar `v6-crud.json` (Parte 2). **La 103 va antes que el workflow**: sin la fila, la entrada nueva nunca se alcanza (el modelo no existe).
4. **Merge a `main`** de este PR, después de (1)-(3) verificados.

Ninguna ventana intermedia cambia lo que ven los usuarios: el frontend no llama todavía al modelo.

## Parte 1 — base de datos (103)

Ejecuta desde la carpeta de las migraciones; guarda la salida de cada paso y no pegues credenciales. **Nada contra producción sin
el respaldo (paso 1) y el dry run (paso 4).**

1. **Respaldo previo:** completo y, además, la tabla del modelo (para restaurar sin `pg_restore` completo):

   ```sh
   pg_dump -Fc -f <RUTA_BACKUP> <BASE_PRODUCCION>
   psql <CONEXION_PRODUCCION> -X -c "\copy (SELECT * FROM crud_models ORDER BY model_name) TO '<RUTA>/crud_models_pre103.csv' CSV HEADER"
   chmod 600 <RUTA_BACKUP> <RUTA>/crud_models_pre103.csv
   ```

2. **Estado ANTES:**

   ```sh
   psql <CONEXION_PRODUCCION> -X -v ON_ERROR_STOP=1 -v expect=before -f 103_state_check.sql | tee <RUTA>/103_before.txt
   ```

   Debe terminar en `STATE OK: before`. Si dice que falta la función de la 102, **detente** (paso 1 del orden).

3. **Dry run:**

   ```sh
   psql <CONEXION_PRODUCCION> -X -v ON_ERROR_STOP=1 -f 103_panel_livestock_gateway_model.sql
   ```

   Debe imprimir `103: OK` y `*** DRY RUN: 103 rolled back ***`. **Detente** si aborta (función ausente, o un modelo con ese nombre ya apunta a otra tabla).

4. **Aplicación:**

   ```sh
   psql <CONEXION_PRODUCCION> -X -v ON_ERROR_STOP=1 -v apply=true -f 103_panel_livestock_gateway_model.sql
   ```

   Debe terminar con `*** 103 COMMITTED ***`.

5. **Estado DESPUÉS:**

   ```sh
   psql <CONEXION_PRODUCCION> -X -v ON_ERROR_STOP=1 -v expect=applied -f 103_state_check.sql | tee <RUTA>/103_after.txt
   diff <RUTA>/103_before.txt <RUTA>/103_after.txt
   ```

   `STATE OK: applied`. Del `diff` solo cambian `checked_at_cdmx`, la fila `=== THE MODEL ROW` y la línea `STATE`; `other_crud_models`,
   `other_crud_models_count` y `sp_register_livestock_panel_md5` deben ser **idénticas**.

## Parte 2 — n8n (gateway v6)

⚠️ Este paso exige que `develop` ya tenga el cambio y el CI esté en verde. `wf_compare.py` es la herramienta de comparación del equipo
(no vive en este repositorio).

6. **Respaldo del workflow:** abre el gateway v6 en producción, **⋯ → Download**, guarda el archivo fuera del repo y `chmod 600`.
7. **Comparación con `main`** (antes de importar): `python3 wf_compare.py <respaldo-produccion.json> <v6-crud.json de origin/main>`
   debe decir `No differences.` (o el equivalente de la herramienta); además la huella de `~/node_fingerprints.py`. Si difiere (producción puede
   traer cambios manuales), **detente**: primero se incorpora ese cambio a `main`.
8. **Comparación con `develop`:** `wf_compare.py <respaldo> <v6-crud.json de develop>` debe mostrar **únicamente `Build Query`** como nodo con
   `parameters` distintos, **sin cambios de conexiones**, y `credentials`, `webhookId`, `typeVersion` y `settings` iguales.
9. **Importación:** en n8n, **⋯ → Import from file…** (mismo workflow), **Save** y **Publish**. No uses `n8n import:workflow`.
10. **Verificación:** descarga el workflow publicado y compara con `develop` (`No differences.`). Después, **prueba real SOLO en la empresa 3,
    sin escritura** (vista previa: `confirmed` vacío o `"false"`), con un ADMIN activo de esa empresa y placeholders en el comando:

    ```sh
    curl -sS -X POST "<URL_GATEWAY_V6>/register_livestock_panel" \
      -H "Authorization: Bearer <TOKEN>" -H "x-tenant-id: 3" -H "Content-Type: application/json" \
      -d '{"action":"call_sp","fields":{"species":"BOVINO","category":"VACA","business_model":"CRIA","ear_tag":"S/N","confirmed":""}}'
    ```

    Esperado: HTTP 200, `error: false` y `data.status = 'preview'` (o `need_info` con las opciones si la empresa 3 tiene varias UPP), con un
    `preview_hash` de 32 hex. Abre la ejecución más reciente y confirma la ruta `Build Query` → `Execute SQL` → `Normalize Data`.
    Con un token de una empresa distinta a la del header debe responder `Respond Tenant Forbidden`; con un rol CUSTOMER, `403`.
    **No se confirma nada en producción.**
11. **Rollback del gateway:** vuelve a importar el respaldo del paso 6, **Save** y **Publish**.

## Rollback de la 103

1. `psql <CONEXION_PRODUCCION> -X -v ON_ERROR_STOP=1 -v apply=true -f 103_rollback.sql` (dry run por defecto; **borra solo** esa fila). Va **antes**
   del rollback de la 102.
2. `103_state_check.sql -v expect=before` debe terminar en `STATE OK: before`.

## Pruebas

* **LOCAL / base descartable:** `psql -X -v ON_ERROR_STOP=1 -f 103_tests.sql` (una transacción que termina en `ROLLBACK`; aplica la 099 y la 102
  solo si faltan). Termina con `103 TESTS: N assertions passed; rolling back` y `no trace left`.
* **Node (sin dependencias):** `node workflows/06-dynamic-crud-engine/v6/tests/test_v6_panel_sp.mjs` (12 comprobaciones del nodo `Build Query`).
  La suite `v5/tests` es del gateway v5 y no cubre este cambio.

## Resultados de la ejecución

Ejecutado por el dueño en una base local descartable (`scratch_100`, PostgreSQL 15.4). **Producción: solo la consulta de lectura de roles; la 103 y
el workflow no se han aplicado.**

| Paso | Resultado |
|---|---|
| `test_v6_panel_sp.mjs` (Node, sin base) | 12 de 12 |
| Preparación local | 102 aplicada con `apply=true` (`102 COMMITTED`); huella de la función `c93653e5a45221e446e80945d1622fc2` |
| `103_state_check.sql -v expect=before` | `STATE OK: before` (fila ausente; `other_crud_models_count` 86, md5 `3fe5a9b610500dc39f905018de0544c2`) |
| Dry run de la 103 | `103: OK` y `DRY RUN: 103 rolled back` |
| Aplicación de la 103 | `103 COMMITTED` |
| `103_state_check.sql -v expect=applied` | `STATE OK: applied`; fila `register_livestock_panel` → `sp_register_livestock_panel`, `allowed_ops {INSERT}`, select/update/delete `NONE`, insert `ADMIN,EDITOR`, `is_global f`, `sp_requires_tenant t`, 18 campos; las otras 86 filas y la función de la 102 con las mismas huellas; la fila directa `cattle_livestock` sigue en `ADMIN,EDITOR` |
| `103_tests.sql` | `27 assertions passed` y `no trace left (crud_models is as before the run)`. PASS: A1, B1-B9, C1-C5, D1, D2, E1-E4, F1-F6. Los mensajes `ERROR` de la salida son esperados: E1 y E3 comprueban que la migración se niega a correr sin la 102 y con un modelo del mismo nombre apuntando a otra tabla |
| Rollback y limpieza locales | `103_rollback.sql` con `apply=true` (`DELETE 1`, `103 ROLLBACK COMMITTED`), `103_state_check.sql -v expect=before` (`STATE OK: before`) y `102_rollback.sql` con `apply=true` (`102 ROLLBACK COMMITTED`); `scratch_100` quedó como antes de la corrida |
| `allowed_roles_insert` de `cattle_livestock` en producción (solo lectura) | `ADMIN,EDITOR` |
| 102 en producción | _pendiente_ |
| 103 en producción (estado antes / dry run / aplicación / después y `diff`) | _pendiente_ |
| Importación del workflow, `wf_compare.py` antes y después | _pendiente_ |
| Prueba real, empresa 3 (vista previa) | _pendiente_ |
