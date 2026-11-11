> ⛔ **NO MERGEAR A `main` HASTA COMPLETAR LA PARTE 1** (base de datos, verificada con sus huellas).
> `main` publica automáticamente los frontends por Plesk: si se mergea antes, el estado del repositorio y el de producción
> divergen.

> **Nota de alcance.** Este PR **no** cambia workflows de n8n ni el frontend: solo agrega la migración 100. No hay Parte 2 de
> n8n; el merge a `main` (Parte 3) es lo último, solo si la Parte 1 está OK. Requiere la 099 aplicada.

# Runbook 100 — normalización del folio de guía en la regularización por chat

## Alcance

El folio de la guía de tránsito que captura el usuario en `sp_register_livestock_regularization` se guardaba solo con
`btrim`, tal como se escribió. La migración 100 lo normaliza a **MAYÚSCULAS** y **colapsa los espacios internos repetidos** a
uno. Los guiones y el resto de los caracteres se conservan. Esa función es la única que usa el folio de la guía (vista previa,
`preview_hash` y `metadata.guide_folio`); por eso `prueba-1` y `PRUEBA-1` producen el mismo `preview_hash`.

| Objeto | Qué hace |
|---|---|
| `fn_livestock_chat_folio(text)` (nueva, `IMMUTABLE`) | `NULL` si `fn_livestock_chat_txt()` da `NULL`; si no, `upper(regexp_replace(<txt>, '\s+', ' ', 'g'))` |
| `sp_register_livestock_regularization` (16 parámetros de texto) | `CREATE OR REPLACE` con el cuerpo de la 099, extraído con un script, y **una sola línea distinta**: `v_folio := public.fn_livestock_chat_folio(p_guide_folio)`. Misma firma, mismo `REVOKE ... FROM PUBLIC` y mismo `COMMENT` |

### Fuera de alcance

* **Sin relleno de filas existentes:** los animales ya registrados conservan el folio que tienen. Ni `UPDATE` ni migración de datos.
* Sin cambios en workflows de n8n ni en frontend. No toca los archivos de la 099 ni la herramienta de compra.

### Comportamiento a tener en cuenta

* El `preview_hash` se calcula con el folio normalizado: una vista previa tomada **antes** de aplicar la 100 y confirmada
  después responde `preview_required` una vez (el agente la vuelve a mostrar). No se pierde ni se escribe nada.
* La 099 rechaza, al aplicarse, cualquier función `fn_livestock_chat_*` que no conozca. Con la 100 aplicada, **vuelve a aplicar
  la 099 solo después de `100_rollback.sql`** (que elimina la auxiliar).

## Orden de despliegue

1. Base de datos: migración 100.
2. n8n: sin cambios.
3. Frontend: sin cambios. El merge a `main` es lo último, solo si 1 está OK.

## Parte 1 — base de datos

Usa una conexión autorizada y guarda la salida de cada paso. Sustituye los placeholders y no pegues credenciales. Ejecuta los
comandos desde la carpeta de las migraciones. **Nada contra producción sin el respaldo (paso 1) y el dry run (paso 4) previos.**

1. **Respaldo previo** (completo, y además la definición actual de la función):

   ```sh
   pg_dump -Fc -f <RUTA_BACKUP> <BASE_PRODUCCION>
   chmod 600 <RUTA_BACKUP>
   psql <CONEXION_PRODUCCION> -X -At -c "SELECT pg_get_functiondef('public.sp_register_livestock_regularization(text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text)'::regprocedure)" > <RUTA>/sp_register_livestock_regularization_antes_100.sql
   chmod 600 <RUTA>/sp_register_livestock_regularization_antes_100.sql
   ```

   Guarda los dos archivos fuera del repositorio. Comprueba que el segundo contiene `fn_livestock_chat_txt(p_guide_folio)`.

2. **Estado ANTES:**

   ```sh
   psql <CONEXION_PRODUCCION> -X -v ON_ERROR_STOP=1 -v expect=before -f 100_state_check.sql | tee <RUTA>/100_before.txt
   ```

   Debe terminar en `STATE OK: before` (`NOT_APPLIED`). Si dice `NO_099` o `PARTIAL`, **detente**.

3. **Conteo de referencia** (solo lectura; permite verificar que la 100 no modifica filas):

   ```sql
   BEGIN TRANSACTION READ ONLY;
   SELECT count(*) AS animales, md5(string_agg(md5(coalesce(metadata::text, '~')), '#' ORDER BY id)) AS huella_metadata
     FROM cattle_livestock;
   ROLLBACK;
   ```

   (`100_state_check.sql` ya imprime una huella equivalente en `=== DATA FINGERPRINT`.)

4. **Dry run:**

   ```sh
   psql <CONEXION_PRODUCCION> -X -v ON_ERROR_STOP=1 -f 100_livestock_folio_normalization.sql
   ```

   Debe imprimir `100: preconditions OK`, `100: OK` y `*** DRY RUN: 100 rolled back ***`. **Detente** si falla una
   precondición (099 sin aplicar, o la herramienta es el stub del rollback de la 099).

5. **Aplicación:**

   ```sh
   psql <CONEXION_PRODUCCION> -X -v ON_ERROR_STOP=1 -v apply=true -f 100_livestock_folio_normalization.sql
   ```

   Debe terminar con `*** 100 COMMITTED ***`.

6. **Estado DESPUÉS:**

   ```sh
   psql <CONEXION_PRODUCCION> -X -v ON_ERROR_STOP=1 -v expect=applied -f 100_state_check.sql | tee <RUTA>/100_after.txt
   diff <RUTA>/100_before.txt <RUTA>/100_after.txt
   ```

   Debe reportar `STATE OK: applied`. Del `diff` solo cambian `checked_at_cdmx`, la sección `=== 100 OBJECTS` (aparece la
   auxiliar y cambia el `md5` de la `sp_*`) y `=== STATE`. `=== DATA FINGERPRINT` debe ser **idéntica** salvo que alguien haya
   capturado o editado un animal entre los pasos 2 y 6.

7. **Humo de solo lectura, empresa 3** (la vista previa no escribe; la transacción es `READ ONLY` y termina en `ROLLBACK`).
   `<CORREO_ADMIN_EMPRESA_3>` es un ADMIN activo de la empresa 3; no lo pegues en el PR:

   ```sql
   BEGIN TRANSACTION READ ONLY;
   SELECT (sp_register_livestock_regularization('3', '<CORREO_ADMIN_EMPRESA_3>', 'CHAT_WEB', '99-999-9999-999', NULL, 'BOVINO',
          'BECERRO', 'CRIA', '8', '9909900003', 'prueba-1', NULL, NULL, 'false', NULL, NULL))->'preview'->>'guia_transito' AS minusculas,
          (sp_register_livestock_regularization('3', '<CORREO_ADMIN_EMPRESA_3>', 'CHAT_WEB', '99-999-9999-999', NULL, 'BOVINO',
          'BECERRO', 'CRIA', '8', '9909900003', 'PRUEBA-1', NULL, NULL, 'false', NULL, NULL))->>'preview_hash' =
          (sp_register_livestock_regularization('3', '<CORREO_ADMIN_EMPRESA_3>', 'CHAT_WEB', '99-999-9999-999', NULL, 'BOVINO',
          'BECERRO', 'CRIA', '8', '9909900003', 'prueba-1', NULL, NULL, 'false', NULL, NULL))->>'preview_hash' AS mismo_hash;
   ROLLBACK;
   ```

   Esperado: `PRUEBA-1` y `mismo_hash = t`. Solo vista previa (`p_confirmed = 'false'`): no se registra ningún animal. Si el
   arete ficticio ya existe, la respuesta será otra: usa otro con prefijo `99`.

## Parte 2 — workflows de n8n

No aplica: la 100 no cambia workflows. Los agentes siguen llamando a la misma función con la misma firma.

## Parte 3 — frontend

Sin cambios. **Solo si la Parte 1 está OK:** publica `develop` → `main` (`gh pr merge N --merge`) y confirma que
`git diff --stat origin/main origin/develop` no imprime nada.

## Plan B — rollback

Sin n8n que restaurar. En la base:

```sh
psql <CONEXION_PRODUCCION> -X -v ON_ERROR_STOP=1 -f 100_rollback.sql                  # dry run
psql <CONEXION_PRODUCCION> -X -v ON_ERROR_STOP=1 -v apply=true -f 100_rollback.sql
psql <CONEXION_PRODUCCION> -X -v ON_ERROR_STOP=1 -v expect=rolled_back -f 100_state_check.sql
```

Restaura la función de la 099 (mismo cuerpo, extraído por script) y elimina `fn_livestock_chat_folio`. **No toca datos:** los
animales registrados mientras la 100 estuvo aplicada conservan su folio en mayúsculas. Debe reportar `STATE OK: rolled_back`.
Para comparar con el respaldo: el `pg_get_functiondef` actual debe coincidir con `sp_register_livestock_regularization_antes_100.sql`
(el `md5` puede variar entre versiones de PostgreSQL; compara el texto del cuerpo). Si hubiera que revertir también la 099,
primero `100_rollback.sql` y después `099_rollback.sql`.

## Pruebas de ensayo (solo LOCAL o copia descartable)

* `100_tests.sql`: una transacción con `ROLLBACK`. **Nunca en producción.** Contiene el cuerpo de `099_tests.sql` (mismos
  ayudantes, empresas sintéticas 9811-9816 y fixtures) con la 100 aplicada justo después de la 099, de modo que las aserciones
  de la 099 corren contra la función nueva; más la sección N (folio en minúsculas y mixto, espacios internos, guion, mismo
  `preview_hash`, placeholder, folio `NULL` con `P0118`, más de 60 caracteres, aislamiento por empresa) y la sección I100 (sin
  relleno de filas, rollback a la 099, nueva aplicación).
* `099_tests.sql` no cambia y sigue probando la 099 sola.
* `100_state_check.sql`: `before`, `applied` y `rolled_back`.
