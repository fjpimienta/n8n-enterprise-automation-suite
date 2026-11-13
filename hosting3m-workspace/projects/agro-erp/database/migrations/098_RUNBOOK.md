> ⛔ **NO MERGEAR A `main` HASTA COMPLETAR LAS PARTES 1 Y 2** (base de datos y n8n, verificadas con sus huellas).
> `main` se despliega manualmente: el dueño entra a Plesk y despliega con git. Si el frontend se despliega antes, si se mergea antes, la pantalla nueva falla en producción.

> **Nota de alcance de este PR.** No hay cambio de workflows de n8n ni de frontend: la Parte 2 es solo verificación por el
> canal real y la Parte 3 no existe. El recuadro se mantiene porque el PR toca la base de datos y el comportamiento del
> agente de ventas depende de ella: si `main` se mergeara antes de la Parte 1, la documentación y el CHANGELOG describirían
> algo que producción todavía no tiene. **Mientras el dry run de producción (Parte 1, paso 1) no haya pasado, el PR no se mergea.**

# Runbook 098 — repasto con retorno (prototipo en la empresa 3)

## Alcance

Una vez aplicada la migración, un animal puede salir de su UPP hacia una UPP de tercero **por guía** (propósito
`REPASTO`) con fecha de retorno esperada, y queda **protegido contra la venta** mientras esté fuera. El estado vive **por
animal** en `cattle_movement_event_animals.return_status`; el estado del movimiento se **calcula** en
`vw_livestock_out_on_loan` y nunca se guarda.

| Objeto | Qué hace |
|---|---|
| `cattle_movement_events.purpose` / `expected_return_date` | `REPASTO` exige fecha de retorno esperada |
| `cattle_movement_event_animals.return_status` / `returned_at` | `NULL` = sin seguimiento (filas históricas); `OPEN`, `RETURNED`, `CANCELLED`, `DIED_AWAY` |
| Índice único parcial `uq_movement_animal_one_open` | un animal no puede estar `OPEN` en dos movimientos |
| `trg_guard_movement_animal_open` | solo se abre un préstamo para un animal vivo que esté en la UPP de origen del movimiento (`P0100`) |
| `trg_block_out_on_loan_status` | con renglón `OPEN`, el animal no pasa a `VENDIDO`, `FINALIZADO` ni `BAJA_DEPURACION_DATOS` (`P0098`) |
| `trg_close_loan_on_death` | si el animal pasa a `BAJA_MORTANDAD`, el renglón se cierra como `DIED_AWAY` |
| `sp_return_movement(event, animals, date, actor_email)` | cierra el retorno por animal (parcial o total); ADMIN/OWNER de la empresa del movimiento (`P0099`) |
| `vw_livestock_out_on_loan` | animales con seguimiento; `event_state` = `OPEN` / `RETURNED` / `CLOSED` |
| `sp_solicitar_venta_orden` | rechaza animales en préstamo («Animal fuera en repasto (guía …, retorno esperado …): no se puede vender») y la selección FIFO los omite |

Códigos de error: **`P0098`** animal fuera, no se vende ni finaliza · **`P0099`** validaciones de `sp_return_movement` ·
**`P0100`** alta de préstamo incoherente (animal vendido, muerto, finalizado o en otra UPP).

### Fuera de alcance (declarado)

* **La carga real de los 31 animales.** Los aretes reales no pueden entrar a la empresa 3 (`rfid_siniiga` es UNIQUE
  global) y la carga real exige decidir empresas de origen (5 y 8), el estado de Santa Lucía (`registry_status =
  'BLOQUEADA'`) y la regularización de padrón. Este PR solo carga el **prototipo** con aretes ficticios.
* **La aparcería** (modelo de propiedad compartida/medias): no está modelada.
* Una herramienta del agente, un modelo `crud_models` o una pantalla para **registrar retornos**. Hoy el retorno se
  registra con SQL (`sp_return_movement`). Cuando exista un consumidor, el correo del actor **debe salir de la sesión
  verificada** (como las tools de palma de la 083), nunca de `$fromAI`.
* Cambios de workflows de n8n y de frontend.
* El script de limpieza física: el prototipo no se borra (ver «Limpieza del prototipo»).

### Dependencia

`sp_return_movement` queda sin `EXECUTE` para `PUBLIC` y sin `GRANT`: depende de que `n8n_user` sea superusuario de
PostgreSQL (nota del `CLAUDE.md` raíz). Si ese rol dejara de serlo, agrega un `GRANT EXECUTE` explícito. Los guardias
viven en la base de datos, pero el aislamiento real sigue dependiendo de que cada llamador pase el tenant verificado.

## Orden de despliegue

1. Base de datos (migración 098, estado, seed del prototipo).
2. Workflows de n8n: **sin cambios**; solo verificación por el canal real.
3. Frontend: **sin cambios**.

## Parte 1 — base de datos

Usa una conexión autorizada y conserva la salida de cada paso. Sustituye los placeholders; no pegues credenciales en el
repositorio ni en logs compartidos. Ejecuta los comandos desde la carpeta de las migraciones.

1. **Dry run en producción — OBLIGATORIO y primero.** Es la única forma de comprobar que las anclas de texto de la
   migración coinciden con la definición viva de `sp_solicitar_venta_orden` **en PG 15.4** (las pruebas locales corrieron en
   PG 16; el formato de `pg_get_functiondef` puede variar entre versiones):

   ```sh
   psql <CONEXION_PRODUCCION> -v ON_ERROR_STOP=1 -f 098_repasto_return_movements.sql
   ```

   Debe imprimir `098 pre-flight: all 4 anchors match the live definition (live md5 …)`, terminar con
   `*** DRY RUN: 098 rolled back ***` y no dejar nada. **Detente y no sigas** si falla la verificación previa
   (`anchors do not match…`, `is not the 097 (FIFO) version`, `partially patched…`) o si falta cualquier tabla: reconstruye la
   migración desde la definición viva revisada; nunca neutralices la verificación. El dry run toma bloqueos breves
   (`ALTER TABLE` sobre las dos tablas de movimientos y `CREATE TRIGGER` sobre `cattle_livestock`): hazlo en una ventana de
   poco tráfico.

2. **Respaldo previo:**

   ```sh
   pg_dump -Fc -f <RUTA_BACKUP> <BASE_PRODUCCION>
   ```

3. **Estado y huellas ANTES.** Guarda toda la salida; el md5 de `orden_def` es el valor «antes» de **este ambiente**
   (no lo compares con el de otro ambiente ni con el del repositorio):

   ```sh
   psql <CONEXION_PRODUCCION> -v ON_ERROR_STOP=1 -v expect=before -f 098_state_check.sql | tee <RUTA>/098_before.txt
   ```

   Debe reportar `STATE OK: before`. Anota `orden_def` como `<MD5_ORDEN_ANTES>`.

4. **Aplicación**, solo después de un dry run limpio y de las huellas:

   ```sh
   psql <CONEXION_PRODUCCION> -v ON_ERROR_STOP=1 -v apply=true -f 098_repasto_return_movements.sql
   ```

   Debe imprimir `098: sp_solicitar_venta_orden patched. md5 before … / after …; properties unchanged (…)` y
   `*** 098 COMMITTED ***`. El «md5 before» debe ser `<MD5_ORDEN_ANTES>`.

5. **Estado y huellas DESPUÉS:**

   ```sh
   psql <CONEXION_PRODUCCION> -v ON_ERROR_STOP=1 -v expect=applied -f 098_state_check.sql | tee <RUTA>/098_after.txt
   diff <RUTA>/098_before.txt <RUTA>/098_after.txt
   ```

   Debe reportar `STATE OK: applied`. Del `diff` solo deben cambiar: las líneas de `=== 098 OBJECTS`, el `orden_def` y la
   marca de tiempo si la hubiera. **Todas las líneas de `=== DATA FINGERPRINTS` deben ser idénticas**, y `sal5_def`, `sal4_def`,
   `sal1_def` y `baja_def` también (la 098 no toca esas funciones). Cualquier otra diferencia: detente.

5b. **Revisión de `crud_models` — OBLIGATORIA antes de seguir.** La 098 protege el estado del animal en la base, pero hay que saber
   qué otras puertas de escritura existen. Corre estas dos consultas (solo lectura) y pega el resultado en el PR:

   ```sql
   -- Modelos que pueden ESCRIBIR sobre el animal o sus movimientos (UPDATE directo por el gateway)
   SELECT model_name, table_name, allowed_ops, allowed_roles_update
     FROM crud_models
    WHERE lower(table_name) IN ('cattle_livestock', 'cattle_movement_events', 'cattle_movement_event_animals')
      AND EXISTS (SELECT 1 FROM unnest(allowed_ops) AS op WHERE upper(op) = 'UPDATE')
    ORDER BY table_name, model_name;

   -- Modelos que invocan procedimientos que cambian el estado o la ubicación del animal
   SELECT model_name, table_name, allowed_ops
     FROM crud_models
    WHERE lower(table_name) IN ('sp_move_livestock', 'sp_procesar_salida_ganado', 'sp_resolver_autorizacion',
                                'sp_procesar_baja_mortandad', 'sp_return_movement')
    ORDER BY table_name, model_name;
   ```

   Para cada fila de la primera consulta decide y anota: (a) el `UPDATE` pasa por el trigger de `cattle_livestock` si cambia
   `current_status` (queda protegido, ver la tabla de rutas); (b) un `UPDATE` de `cattle_movement_event_animals` permite escribir
   `return_status` a mano, saltándose `sp_return_movement` (no se valida rol ni fecha): si hay un modelo así, quítale `UPDATE` o
   restríngelo a ADMIN antes de desplegar. Si la segunda consulta devuelve `sp_return_movement`, detente: la 098 no registra ese
   modelo (ver «Fuera de alcance»). En la copia local la tabla está vacía, por lo que esta revisión solo tiene sentido en
   producción.

6. **Seed del prototipo (empresa 3).** El script escribe solo filas de la empresa 3 y **aborta si la empresa 3 no existe**
   (nunca la crea sin `-v allow_create_company=true`; no uses esa opción en producción). Primero dry run:

   ```sh
   psql <CONEXION_PRODUCCION> -v ON_ERROR_STOP=1 -f 098_seed_repasto_prototipo.sql
   psql <CONEXION_PRODUCCION> -v ON_ERROR_STOP=1 -v apply=true -f 098_seed_repasto_prototipo.sql
   ```

   Debe terminar con `31 OPEN in company 3`. **`business_model` quedó en `CRIA` sin confirmar con el dueño:** si cambia,
   vuelve a correr el seed con `-v business_model=<VALOR>` solo si aún no se aplicó; después, corrige con un `UPDATE`
   revisado. El seed es idempotente (una segunda ejecución crea 0 filas). Verifica:

   ```sql
   SELECT reemo_folio, event_state, count(*) FROM vw_livestock_out_on_loan WHERE id_company = 3 GROUP BY 1, 2 ORDER BY 1;
   -- 7139728 → 13, 7139729 → 17, PRUEBA-3A-GUIA → 1, todos OPEN
   ```

7. **Prueba funcional en producción — solo empresa 3.** No uses animales ni usuarios reales ni otra empresa. Todo con
   `BEGIN … ROLLBACK`. Con el seed del paso 6 ya aplicado, comprueba, por ejemplo con un animal del prototipo:

   ```sql
   BEGIN;
   UPDATE cattle_livestock SET current_status = 'VENDIDO'
    WHERE tenant_id = 3 AND rfid_siniiga = '9924388351';   -- debe fallar con P0098
   ROLLBACK;
   ```

8. **Verificación por el canal real, empresa 3** (WhatsApp o Chat Web con un usuario ADMIN de la empresa 3; **nunca** desde el
   panel de chat del editor de n8n ni con otra empresa). Pide vender el animal `9924388351` con una guía cualquiera. El agente
   llama a `preview_livestock_sale_order` y **debe relatar** el error de la base:
   «Animal fuera en repasto (guía 7139728, retorno esperado 2026-12-14): no se puede vender». Responde **«No»** al final: no
   confirmes ninguna orden. Guarda el id de la ejecución. Si el agente parafrasea o esconde el motivo, regístralo como
   hallazgo (el ajuste del prompt queda fuera de este PR).

9. **Retorno ficticio (opcional, para demostrar la vista):**

   ```sh
   psql <CONEXION_PRODUCCION> -v ON_ERROR_STOP=1 -f 098_seed_return_demo.sql
   psql <CONEXION_PRODUCCION> -v ON_ERROR_STOP=1 -v apply=true -v guide=7139729 -f 098_seed_return_demo.sql   # parcial
   ```

   Es un `UPDATE` directo, solo empresa 3 (aborta si algún renglón es de otra), con fecha ficticia `2026-12-10`. **No es la
   forma de registrar un retorno real**; `sp_return_movement` rechaza fechas futuras a propósito.

## Parte 2 — workflows de n8n

Sin cambios. Solo ejecuta el paso 8 de la Parte 1. No importes ni publiques workflows por este PR.

## Parte 3 — frontend

Sin cambios.

## Pruebas de ensayo (solo LOCAL o copia descartable con esquema compatible)

* `098_tests.sql`: 83 aserciones en una transacción que termina en `ROLLBACK`. **Nunca en producción** (crea empresas de
  prueba y deshabilita un trigger dentro de la transacción). Se corre desde la carpeta de migraciones porque aplica la 098 y su
  rollback con `\i`.
* `098_mutation_check.sh`: rompe, una por una, seis protecciones (trigger de venta, bloque de la orden, índice único, `P0100`,
  exclusión FIFO, cierre `DIED_AWAY`) y exige que falle la prueba correspondiente; el control sin mutación debe pasar.
* `098_concurrency_check.sh`: venta contra alta `OPEN` del mismo animal con dos sesiones `psql`, en los dos órdenes. **Confirma
  datos** (empresa 9891) y los borra al terminar, por eso solo corre en una copia vacía (sin animales) con la 098 aplicada,
  confirmada y con sus tres triggers habilitados; si no, aborta. Nunca en producción ni en un clon con datos.
  **Resultado (2026-11-04, copia descartable `hosting3m_schema`, PG 16.15):** orden 1 (venta primero) → el alta esperó 3.5 s y
  falló con `P0100`; orden 2 (alta primero) → la venta esperó 3.5 s y falló con `P0098`; sin interbloqueo, empresa 9891 borrada.
  Con el guardia sin `FOR SHARE` la misma prueba falla en los dos órdenes (no hay espera y se pierde la protección), así que la
  prueba sí detecta esa regresión.

Procedimiento manual equivalente (dos terminales, copia descartable con la 098 aplicada y un animal `ACTIVO` en una UPP con
un movimiento `REPASTO` de origen en esa UPP):

1. Terminal 1: `BEGIN; UPDATE cattle_livestock SET current_status = 'VENDIDO' WHERE id = '<A>'; SELECT pg_sleep(30);`
2. Terminal 2, mientras corre el sueño: `INSERT INTO cattle_movement_event_animals (event_id, cattle_livestock_id, return_status) VALUES ('<EV>', '<A>', 'OPEN');` — debe **quedar esperando**.
3. Terminal 1: `COMMIT;` — la terminal 2 debe fallar con `P0100`.
4. Invierte: terminal 1 `BEGIN; INSERT … 'OPEN' (animal B); SELECT pg_sleep(30);`; terminal 2 `UPDATE … 'VENDIDO'` (animal B) — espera; al `COMMIT` de la 1, la 2 falla con `P0098`.

Si cualquiera de las dos esperas no ocurre, o el segundo paso termina sin error, hay una protección perdida: no despliegues.

## Rutas cuya protección depende SOLO del trigger de `cattle_livestock`

El bloqueo explícito (mensaje «Animal fuera en repasto…») solo existe en `sp_solicitar_venta_orden`. Estas rutas no revisan los
préstamos por sí mismas y quedan cubiertas únicamente por `trg_block_out_on_loan_status` (`P0098`):

| Ruta | Estado de la verificación |
|---|---|
| `sp_procesar_salida_ganado(character varying)` (overload de 1 parámetro, legacy) | **No ejecutado directamente.** Una llamada simple es ambigua (`42725`) con el overload de 5, así que no es alcanzable sin OID o SQL dinámico; el trigger la cubriría porque hace el mismo `UPDATE` |
| `sp_procesar_salida_ganado(…)` (overload de 4 parámetros) | **No ejecutado directamente**, por la misma ambigüedad |
| `sp_procesar_salida_ganado(…)` (overload de 5 parámetros: modelo `salida_ganado` del gateway) | Probado: por uuid, por arete SINIIGA y por chip → `P0098` |
| `sp_resolver_autorizacion` → `sp_procesar_venta_autorizada` al aprobar una venta (la ruta real de aprobación; no pasa por `sp_procesar_salida_ganado`) | Probado (I3 a I6): una solicitud `PENDIENTE` creada antes del préstamo falla al aprobar con `P0098`, queda `PENDIENTE`, el animal sigue `ACTIVO` y no se registra ingreso. El préstamo **sí** se permite aunque haya una venta pendiente; un ADMIN la libera rechazándola |
| `UPDATE cattle_livestock SET current_status = …` directo (SQL o Meta-CRUD) | Probado → `P0098` (Meta-CRUD lo entrega como HTTP 200 con `error:true`: inspecciona siempre el cuerpo) |
| `DELETE` físico de un animal con renglón de movimiento | Lo impide la llave foránea de `cattle_movement_event_animals` (sin `ON DELETE CASCADE`); no es una protección de la 098 |

Qué **no** bloquea la 098, por diseño o por alcance:

* `BAJA_MORTANDAD`: se permite y cierra el renglón como `DIED_AWAY`. La fecha de la muerte vive en `mortality_events`;
  `returned_at` es el momento en que se registró la baja (`now()`).
* Cambios a estados no terminales (`PREÑADA`, `VACÍA`, `CUARENTENA`, …).
* **Deuda abierta — `sp_move_livestock`:** mueve a un animal de lote (dentro de la misma UPP; solo hace `UPDATE … SET lot_id`) sin
  mirar los préstamos, así que un animal con renglón `OPEN` puede cambiar de lote mientras está fuera. Cambiar su
  `production_unit_id` por otra vía (un `UPDATE` directo, un modelo de Meta-CRUD) tampoco está bloqueado: el guardia solo mira la UPP
  cuando se abre el préstamo, y el retorno no la valida. Impacto: datos inconsistentes (un animal «fuera» que figura en otro lote
  o UPP), no una venta no autorizada. Decisión pendiente: bloquear ambos cambios con `P0098` mientras haya renglón `OPEN`, o
  validar la UPP y el lote en `sp_return_movement`.
* Un superusuario puede deshabilitar los triggers con `ALTER TABLE … DISABLE TRIGGER`. El rollback de la 098 lo hace a
  propósito.

La revisión de `crud_models` (paso 5b de la Parte 1) es obligatoria y su resultado va en el PR.

## Rollback

Después de respaldar y de confirmar el estado aplicado. **Mientras el rollback esté activo, los animales con renglón `OPEN` no
tienen protección de venta**; el script imprime cuántos son. Revísalo y decide:

```sh
psql <CONEXION_PRODUCCION> -v ON_ERROR_STOP=1 -f 098_rollback.sql                       # dry run
psql <CONEXION_PRODUCCION> -v ON_ERROR_STOP=1 -v apply=true -f 098_rollback.sql
psql <CONEXION_PRODUCCION> -v ON_ERROR_STOP=1 -v expect=rolled_back \
  -v expect_md5_orden=<MD5_ORDEN_ANTES> -f 098_state_check.sql
```

* No hay `DROP` ni `DELETE`: `sp_solicitar_venta_orden` vuelve **byte a byte** a su definición anterior (lo confirma el md5
  guardado en el paso 3, del mismo ambiente), los tres triggers quedan deshabilitados, `sp_return_movement` responde
  `{"status":"disabled"}` y la vista queda vacía. Columnas, CHECK e índice quedan sin uso.
* Los renglones no se tocan: volver a aplicar la 098 restaura la protección con el mismo estado.
* `-v cancel_open=true` marca como `CANCELLED` los renglones `OPEN` cuyo animal tenga `production_unit_id`; los que no lo tengan se
  omiten, quedan `OPEN` y se reportan (el trigger de tenant los rechazaría al actualizar).
* La última comprobación debe reportar `STATE OK: rolled_back` y `sp_solicitar_venta_orden md5 matches the recorded pre-098 value`.

## Limpieza del prototipo

El borrado es **lógico**, nunca físico, y no tiene script en este PR. Cuando el prototipo ya no sirva: primero cierra los
renglones (`CANCELLED` o `RETURNED`) y solo después pasa los animales de prueba a `BAJA_DEPURACION_DATOS` (con renglón `OPEN` el
trigger lo rechaza). Hazlo con un script propio, con dry run y respaldo, y solo sobre filas con `metadata.source =
'PROTOTIPO_REPASTO'` y `tenant_id = 3`.

## Notas operativas

* **Estado del movimiento** (`event_state`): `OPEN` si algún renglón está `OPEN`; `RETURNED` si ninguno está abierto y al menos uno
  `RETURNED`; `CLOSED` en otro caso (todos `CANCELLED` o `DIED_AWAY`).
* `sp_return_movement(p_animals => NULL)` cierra todos los `OPEN`; una lista vacía falla con `P0099`; repetir un retorno con lista
  explícita devuelve `returned=0, already_closed=N`; es idempotente.
* El retorno nunca modifica `cattle_livestock`: `production_unit_id`, `lot_id` y `upp_origen` quedan como estaban.
* Las pruebas de esta migración encontraron un fallo que el dry run no puede ver: un alias SQL con el nombre de una variable
  PL/pgSQL de la función parcheada. Por eso **ninguna prueba se sustituye por el dry run**, y viceversa.
