> ⛔ **NO MERGEAR A `main` HASTA COMPLETAR LA PARTE 1** (base de datos, verificada con sus huellas).
> `main` se despliega manualmente: el dueño entra a Plesk y despliega con git. Si el frontend se despliega antes, si se mergea antes, la pantalla nueva falla en producción.

> **Nota de alcance.** Este PR **no** cambia workflows de n8n. Cambia una vista de la base de datos (migración 101) y el
> componente de la Bitácora del frontend. No hay Parte 2 de n8n. La parte del frontend (Parte 3) es siempre la última y empieza
> con «solo si la Parte 1 está OK». Requiere la 099 aplicada (de ahí salen las altas) y la 067 (definición vigente de la vista).

# Runbook 101 — altas por regularización de padrón en la Bitácora de eventos

## Alcance

`vw_cattle_event_log` (última definición: migración 067) no tenía rama para los animales dados de alta con la herramienta de
regularización de padrón (migración 099, `cattle_livestock.metadata->>'source' = 'REGULARIZACION_PADRON'`): no aparecían en la
Bitácora. La 101 agrega **una rama** `REGULARIZACION`, calcada de la de `COMPRA`:

| Elemento | Valor |
|---|---|
| Filas | una por animal con `metadata->>'source' = 'REGULARIZACION_PADRON'` |
| `event_type` | `'REGULARIZACION'` |
| `event_date` | `fn_event_ts_cdmx(NULL, cl.created_at)` (hora de CDMX del alta; no hay fecha de compra) |
| `created_at` | `fn_utc_to_cdmx(cl.created_at)` |
| `weight_kg` | `cl.current_weight_kg` (suele ser `NULL`) |
| `description` | `concat_ws(' — ', …)` con `guide_folio`, `origin_upp_code`, `reported_age_months`, `category_reported`, `channel` y `notes`; los datos que faltan se omiten. **No** incluye `preview_hash` ni `registered_by` |
| Columnas | las mismas 18, con los mismos tipos (la huella de columnas no cambia) |

La Bitácora sigue siendo solo ADMIN (migración 064, `crud_models`); la 101 no toca `crud_models` ni los permisos de la vista
(`CREATE OR REPLACE VIEW` conserva la ACL).

### Fuera de alcance

* Sin relleno ni cambios de datos: no se modifica ningún animal.
* Sin cambios en funciones, tablas, workflows ni en la 099.
* Las altas por compra y el resto de ramas no cambian (la prueba compara cada fila de la vista antes y después).

## Comportamiento entre la base y el frontend

⚠️ El endurecimiento del componente (tipos desconocidos mostrados tal cual, badge neutro, orden, agrupación y CSV sin error)
protege **solo el frontend nuevo**. El frontend que está hoy en producción **no** lo tiene: con la base ya aplicada y ese
frontend anterior, las filas `REGULARIZACION` se listan con el badge vacío y sin color, y **ordenar la Bitácora por «Tipo de
evento» falla** (la tabla deja de renderizarse) mientras haya una fila `REGULARIZACION` junto a otras. Agrupar por tipo crea un
grupo sin nombre y el CSV deja vacía la columna de tipo. No se pierde ni se escribe ningún dato.

Por eso el orden es obligatorio y la ventana debe ser mínima: aplicar la base, hacer el merge a `main` y desplegar el frontend
con Plesk **Deploy now** enseguida (ver el orden de despliegue).

## Orden de despliegue

1. Base de datos: migración 101 (primero).
2. n8n: sin cambios.
3. Merge a `main` y frontend (Plesk **Deploy now**) **enseguida** después de aplicar la base; no dejes la base aplicada con el frontend anterior. `main` se despliega manualmente: el dueño lo hace en Plesk con git; si el sitio no refleja la release, en la sección Git del dominio usa
   **Deploy now** y fuerza la recarga del navegador. Solo cuando se libere a `main`.

## Parte 1 — base de datos

Usa una conexión autorizada y guarda la salida de cada paso. Sustituye los placeholders y no pegues credenciales. Ejecuta los
comandos desde la carpeta de las migraciones. **Nada contra producción sin el respaldo (paso 1) y el dry run (paso 4) previos.**

1. **Respaldo previo** (completo, y además la definición actual de la vista):

   ```sh
   pg_dump -Fc -f <RUTA_BACKUP> <BASE_PRODUCCION>
   chmod 600 <RUTA_BACKUP>
   psql <CONEXION_PRODUCCION> -X -At -c "SELECT pg_get_viewdef('public.vw_cattle_event_log'::regclass, true)" > <RUTA>/vw_cattle_event_log_antes_101.sql
   chmod 600 <RUTA>/vw_cattle_event_log_antes_101.sql
   ```

   Guarda los dos archivos fuera del repositorio. Comprueba que el segundo contiene `'COMPRA'::text AS event_type` y **no**
   contiene `REGULARIZACION`.

2. **Estado ANTES:**

   ```sh
   psql <CONEXION_PRODUCCION> -X -v ON_ERROR_STOP=1 -v expect=before -f 101_state_check.sql | tee <RUTA>/101_before.txt
   ```

   Debe terminar en `STATE OK: before` (`has_branch = f`, `normalized_viewdef_md5 = 726fdf2e20ca6848deb0b1d7cfef66b9`).
   Anota `columns` (18) y `columns_md5`. Si dice `PARTIAL`, **detente**: la definición de producción no es la de la 067 (o el
   motor deparsa distinto; compara el respaldo con `067_event_log_cdmx_timezone.sql` antes de seguir).

3. **Conteo de referencia** (solo lectura):

   ```sql
   BEGIN TRANSACTION READ ONLY;
   SELECT count(*) AS filas_vista FROM vw_cattle_event_log;
   SELECT count(*) AS animales_regularizacion FROM cattle_livestock WHERE metadata->>'source' = 'REGULARIZACION_PADRON';
   ROLLBACK;
   ```

   Esperado después: `filas_vista` aumenta en exactamente `animales_regularizacion`.

4. **Dry run:**

   ```sh
   psql <CONEXION_PRODUCCION> -X -v ON_ERROR_STOP=1 -f 101_event_log_regularization.sql
   ```

   Debe imprimir `101: preconditions OK`, `101: OK` y `*** DRY RUN: 101 rolled back ***`. **Detente** si falla una precondición
   (columnas distintas de las 18 esperadas, definición distinta de la 067, funciones `fn_*_cdmx` ausentes).

5. **Aplicación:**

   ```sh
   psql <CONEXION_PRODUCCION> -X -v ON_ERROR_STOP=1 -v apply=true -f 101_event_log_regularization.sql
   ```

   Debe terminar con `*** 101 COMMITTED ***`. Si la vista ya tiene la rama, imprime un `NOTICE` y no cambia nada.

6. **Estado DESPUÉS:**

   ```sh
   psql <CONEXION_PRODUCCION> -X -v ON_ERROR_STOP=1 -v expect=applied -f 101_state_check.sql | tee <RUTA>/101_after.txt
   diff <RUTA>/101_before.txt <RUTA>/101_after.txt
   ```

   Debe reportar `STATE OK: applied`. Del `diff` solo cambian `checked_at_cdmx`, `normalized_viewdef_md5`, `has_branch` y
   `rows_in_view`. **`columns` y `columns_md5` deben ser idénticos.**

7. **Prueba en producción (solo lectura, tenant 3 «Rancho El Palomar»):**

   ```sql
   BEGIN TRANSACTION READ ONLY;
   SELECT event_type, count(*) FROM vw_cattle_event_log WHERE tenant_id = 3 GROUP BY 1 ORDER BY 1;
   SELECT v.event_type, v.event_date, v.rfid_siniiga, v.description
     FROM vw_cattle_event_log v
     JOIN cattle_livestock cl ON cl.id = v.livestock_id
    WHERE v.tenant_id = 3 AND cl.metadata->>'source' = 'REGULARIZACION_PADRON'
    ORDER BY v.event_date DESC LIMIT 5;
   SELECT count(*) AS en_vista FROM vw_cattle_event_log WHERE tenant_id = 3 AND event_type = 'REGULARIZACION';
   SELECT count(*) AS animales FROM cattle_livestock WHERE tenant_id = 3 AND metadata->>'source' = 'REGULARIZACION_PADRON';
   ROLLBACK;
   ```

   Esperado: `en_vista = animales`, cada animal con exactamente una fila `REGULARIZACION`, y una descripción que empieza con
   «Alta por regularización de padrón» y no contiene hashes ni correos. Si el tenant 3 no tiene altas por regularización, la
   consulta devuelve 0 en ambos conteos (también correcto); en ese caso la comprobación visual espera a una alta real.

## Parte 2 — workflows de n8n

No aplica: la 101 no cambia workflows.

## Parte 3 — frontend

**Solo si la Parte 1 está OK.** Cambia `cattle-event-log` (tipo `REGULARIZACION`: etiqueta, filtro «Regularización», color y
detalle; además tolera tipos desconocidos) y agrega sus pruebas. Publica `develop` → `main` (`gh pr merge N --merge`), confirma que
`git diff --stat origin/main origin/develop` no imprime nada y, si Plesk no refleja la release, **Deploy now** y recarga forzada.
Comprueba en la pestaña «Cattle Event Log», con un ADMIN, que las altas por regularización aparecen con el tipo
«Regularización», que el filtro de tipo las aísla y que ordenar y agrupar por tipo funcionan.

## Plan B — rollback

Sin n8n que restaurar. En la base:

```sh
psql <CONEXION_PRODUCCION> -X -v ON_ERROR_STOP=1 -f 101_rollback.sql                  # dry run
psql <CONEXION_PRODUCCION> -X -v ON_ERROR_STOP=1 -v apply=true -f 101_rollback.sql
psql <CONEXION_PRODUCCION> -X -v ON_ERROR_STOP=1 -v expect=before -f 101_state_check.sql
```

Restaura exactamente la definición de la 067 (mismas 18 columnas). **No toca datos.** Debe reportar `STATE OK: before` y el
`normalized_viewdef_md5` del paso 2. Para comparar con el respaldo: el `pg_get_viewdef` actual debe coincidir con
`vw_cattle_event_log_antes_101.sql`. El frontend con el tipo nuevo funciona igual sin esas filas.

## Pruebas de ensayo (solo LOCAL o copia descartable)

* `101_tests.sql`: una transacción con `ROLLBACK`. **Nunca en producción.** Necesita una base con las migraciones 060–067 (la
  vista en su estado de la 067) y `cattle_livestock`; crea empresas y animales sintéticos (9831, 9832). Comprueba: un animal
  `REGULARIZACION_PADRON` aparece con `event_type = 'REGULARIZACION'` y una sola fila; las filas de la vista anterior (COMPRA,
  PESO, SALUD, PARTO, …) siguen idénticas; un animal de otra empresa no aparece al filtrar por tenant; columnas y tipos
  idénticos; idempotencia; el rollback devuelve la definición original (`md5` normalizado); un animal sin `source` no genera fila;
  y `preview_hash` / correo no se exponen.
  ```sh
  psql -X -v ON_ERROR_STOP=1 -d <BASE_DESCARTABLE> -f 101_tests.sql
  ```
* `101_state_check.sql`: `before`, `applied` y `rolled_back` (sinónimo de `before`).
* **Resultado de la ejecución local** (copia descartable `scratch_100`, PostgreSQL 15.4, ejecutada por el responsable del
  proyecto): `101_tests.sql` completo con todos los casos en PASS (A1–A3, B1–B12, C1, D1–D2, E1–E6, F1–F2); verificación de
  estado `before` / `applied` / `before`; dry run, aplicación y rollback correctos. Huellas: `md5` normalizado de la vista 067 =
  `726fdf2e20ca6848deb0b1d7cfef66b9`; con la rama nueva = `554ef4c142662231c69799f0bfe4a1f0`; huella de las 18 columnas =
  `e8d03ea948ef51a6d533127c34d990a9` (idéntica antes y después). **Pendiente solo la aplicación en producción.**
* Frontend: `ng test agro-erp` (incluye `cattle-event-log.component.spec.ts`) y `ng build agro-erp --configuration=production`.
