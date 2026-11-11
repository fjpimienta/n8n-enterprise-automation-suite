> ⛔ **NO MERGEAR A `main` HASTA COMPLETAR LA PARTE 1** (base de datos, verificada con sus huellas).
> `main` publica automáticamente los frontends por Plesk: si se mergea antes, el estado del repositorio y el de producción
> divergen.

> **Nota de alcance.** Este PR **no** cambia workflows de n8n, el gateway (`v6-crud.json`), `crud_models` ni el frontend: solo
> agrega la migración 102 (una función nueva sin consumidores). **No cambia ningún comportamiento visible** hasta los PR 2-4
> (modelo del gateway, servicio y pantalla del panel). No hay Parte 2 de n8n; el merge a `main` (Parte 3) es lo último, solo si
> la Parte 1 está OK. Requiere la 099 aplicada (la 100 no es necesaria).

> ⚠️ **ESTADO: los SQL de este PR están SIN EJECUTAR.** Quien los escribió no tiene base de datos ni puede correrlos. Hasta que
> la persona que los ejecute en una base local descartable reporte los resultados (sección «Resultados de la ejecución»), todo
> lo que dice este runbook sobre su comportamiento es **diseño, no evidencia**.

# Runbook 102 — alta de ganado del panel web: función de vista previa y confirmación

## Alcance

El alta del panel (`cattle-detail-modal`, acción `ALTA`) hoy inserta directo en `cattle_livestock` por el gateway. La 102 agrega
**una sola función**, `sp_register_livestock_panel`, con los mismos resguardos de la 099 (empresa y actor verificados, UPP
resuelta dentro de la empresa, duplicados, vista previa, confirmación con `preview_hash`, `metadata.source`). Reutiliza los
ayudantes `fn_livestock_chat_*` de la 099 **sin modificarlos**.

| Objeto | Qué hace |
|---|---|
| `sp_register_livestock_panel` (19 parámetros: `p_tenant_id integer` + 18 `text`) | Dos pasos: con `confirmed` distinto de `true` solo valida y responde `preview`; con `true` y el `preview_hash` exacto escribe. `REVOKE ALL ... FROM PUBLIC`. |

Orden de los parámetros (el PR 2 lo copiará en `spConfigByModel`, con el tenant en la posición 0 y `actor_email` al final):
`tenant_id`, `upp`, `lot`, `species`, `category`, `business_model`, `ear_tag`, `fire_number`, `electronic_rfid`, `weight_kg`,
`birth_date`, `origin_upp`, `tb_test_date`, `br_test_date`, `notes`, `confirmed`, `preview_hash`, `force_duplicate`, `actor_email`.
El canal (`PANEL_WEB`) lo fija la función; no viaja del cliente.

### Reglas (decididas por el dueño del proyecto)

* **Peso opcional** (queda `NULL`). **TB y BR opcionales**, con aviso si faltan o tienen más de 60 días (solo bovinos sin dictamen
  de hato libre de la UPP: es la regla de `sp_procesar_salida_ganado`).
* **Arete vacío o `S/N`** (también `SN`, `s/n`, «sin arete»…) en cualquier especie, con aviso en la vista previa. **Nunca se guarda
  el literal `S/N`**: el animal recibe `S/N-<empresa>-<10 hex de su propio id>` y `metadata.no_official_tag = true`. Para un bovino
  el aviso dice que **no podrá venderse ni darse de salida hasta tener arete SINIIGA de 10 dígitos**.
* Un arete escrito se guarda tal cual, salvo en bovinos, donde debe ser de 10 dígitos (como en la 099); si no, `need_info` con la
  indicación de dejarlo vacío o escribir `S/N`.
* **Fecha de nacimiento tal cual** (animales nacidos en el rancho); vacía = hoy en CDMX (`fn_livestock_chat_today`). No puede ser
  futura ni anterior a 40 años; nunca se estima por edad.
* **UPP** con `fn_livestock_chat_resolve_upp`: una sola activa → por defecto; varias sin indicar → `need_info` con las opciones;
  ninguna → `need_info`. Se guardan `production_unit_id` y el lote; `upp_origen` (texto libre, hasta 100 caracteres) va a la columna.
* `metadata`: `source = 'PANEL_ALTA'`, `registered_by`, `channel = 'PANEL_WEB'`, `registered_at`, `notes`, `tool`, `migration = '102'`,
  `no_official_tag`. **Sin `preview_hash`** ni datos sensibles.
* Estados como en la 099: `preview`, `preview_required`, `recorded`, `need_info`, `duplicate`, `duplicate_other_company`,
  `exists_without_upp`, `duplicate_recent`, `forbidden`, `palm`, `invalid`; `preview_hash` de 32 hex; la vista previa no escribe.
* Fail-closed: `fn_livestock_chat_ctx` (tenant entero → miembro activo de empresa activa → no palma → rol ADMIN/OWNER/EDITOR) antes
  de cualquier lectura o escritura. **Los permisos por rol del gateway van en el PR 2 (`crud_models`); aquí no se definen.**

### Fuera de alcance

* Ni gateway, ni `crud_models`, ni frontend, ni workflows. La Bitácora (`vw_cattle_event_log`) y cualquier otra vista **no cambian**:
  los altas del panel (`source = 'PANEL_ALTA'`) no aparecen en la Bitácora (deuda documentada, como la de la 099 antes de la 101).
* Sin relleno de filas existentes, sin `UPDATE`/`DELETE` de datos, sin tablas, vistas, disparadores, índices, secuencias ni permisos.

### Comportamiento a tener en cuenta

* Si la fecha de nacimiento viene vacía y el día de CDMX cambia entre la vista previa y la confirmación, el `preview_hash` cambia y
  la función responde `preview_required` una vez (se vuelve a mostrar). No se pierde ni se escribe nada.
* El peso se lee como la 099: `412.5` o `450 kg`; **la coma se toma como separador de miles** (`412,5` = 4125). El frontend debe
  normalizar el decimal.
* `S/N-…` tiene 10 hex de un id aleatorio: una colisión (≈ 2⁻⁴⁰) se reintenta hasta 5 veces con otro id; la restricción `UNIQUE`
  global de `rfid_siniiga` es la última línea.
* La 099 aborta si encuentra una firma `fn_livestock_chat_*` desconocida; la 102 **no agrega ninguna** (la función se llama
  `sp_register_livestock_panel` y no tiene ayudantes), así que la 099 puede volver a aplicarse. No es necesario revertir la 102 antes.

## Verificaciones hechas leyendo las migraciones (sin ejecutar nada)

**(a) ¿Existe una restricción única de `(tenant_id, rfid_siniiga)`?** **No.** La restricción es `cattle_livestock_rfid_siniiga_key`,
`UNIQUE` **global** sobre `rfid_siniiga` solo (y `cattle_livestock_electronic_rfid_key` sobre `electronic_rfid`). Evidencia:
`099_livestock_regularization.sql:55-56` («UNIQUE, global») y `:106-110` (la precondición exige las dos restricciones),
`099_state_check.sql:65`, `099_RUNBOOK.md:48`, `098_RUNBOOK.md:35` y `098_seed_repasto_prototipo.sql:8` («`rfid_siniiga` is UNIQUE across
the whole database»). La definición original de la tabla no está versionada en el repo (solo se verifica por nombre).
*Consecuencia para la decisión 3:* el identificador `S/N-` debe ser único en **toda** la base, no solo por empresa. Cumple: lleva la
empresa y 10 hex del id del animal, y la restricción global lo respalda con reintento. No contradice la decisión.

**(b) ¿`current_weight_kg` y `production_unit_id` aceptan `NULL`?**
* `production_unit_id`: **sí**. `load_ganado_rojo.py:30` («`production_unit_id` … left NULL — this is schema-legal»);
  `016_cattle_livestock_production_unit_link.sql:~30` (el disparador regresa `NEW` si es `NULL`); animales de la 099 y 100 de
  empresas sin UPP en pruebas (`099_tests.sql`, `exists_without_upp`).
* `current_weight_kg`: **evidencia en conflicto — el repositorio no lo resuelve.**
  * A favor de `NULL`: la 099 inserta `NULL` en la regularización (`099_livestock_regularization.sql:793-794`) y sus pruebas lo
    afirman (`099_tests.sql:343`, `100_tests.sql:339`: `current_weight_kg IS NULL`); la 099 está desplegada desde 2026-11-10 y el
    CHANGELOG (#993) ya describe animales «sin peso registrado».
  * En contra: scripts de carga de 2026-08 dicen «`current_weight_kg` is NOT NULL in production (discovered 2026-08-04)»
    (`upsert_adult_cattle.py:295`, `load_ganado_rojo.py:35`, `038_alta_toros_tenosique.sql:21`) y usaban `0` +
    `metadata.peso_no_registrado`.
  * **Lo que hace la 102:** la decisión 2 (peso opcional) la sigue la 099 como precedente, pero la 102 **no lo supone**: su
    precondición **aborta** (antes de crear nada) si `cattle_livestock.current_weight_kg` (o `production_unit_id`, `rfid_siniiga`,
    `electronic_rfid`, `numero_fuego`, `lot_id`, `upp_origen`, `tb_test_date`, `br_test_date`) es `NOT NULL`; `102_state_check.sql`
    imprime `is_nullable` de esas columnas y falla igual. **Antes del dry run, ejecuta la consulta de solo lectura del paso 2b.** Si
    el peso resulta `NOT NULL` en producción, detente y reporta: la decisión 2 cambiaría (p. ej. guardar `0` + marca).

**(c) Especies, categorías y etapas.**
* Categorías permitidas por `cattle_livestock_category_check` (`029_add_equine_species_support.sql:30-37`): `VACA, TORO, NOVILLO,
  NOVILLONA, BECERRA, BECERRO, BUFALA, BUFALO, BUCERRO, BUCERRA, BORREGO, BORREGA, CABALLO, YEGUA, POTRO, POTRANCA, CABALLO_CASTRADO`.
  Las cuatro del panel (`VACA`, `TORO`, `NOVILLO`, `BECERRA`) están.
* Etapas de `cattle_lifestage_catalog` para BOVINO (`008_cattle_lifestage_catalog.sql:34-39`): `BECERRA→NOVILLONA`,
  `NOVILLONA→VACA`, `BECERRO→NOVILLO`, `NOVILLO→TORO`; producción añade `BECERRO_TORETE→TORO` (`099_tests.sql` lo reproduce;
  `085_repro_empadre.sql:440`). `fn_livestock_chat_valid_categories('BOVINO')` toma las categorías de origen y destino del catálogo
  (`099_livestock_regularization.sql:437-455`): `BECERRA, BECERRO, BECERRO_TORETE, NOVILLONA, NOVILLO, VACA, TORO`. Las demás especies
  usan listas fijas (BORREGO: `BORREGA, BORREGO`; BUFALO: `BUCERRA, BUCERRO, BUFALA, BUFALO`; EQUIDO: `CABALLO, CABALLO_CASTRADO,
  POTRANCA, POTRO, YEGUA`).
* Especies: `species` no tiene `CHECK` propio y su valor por defecto es `BOVINO` (`029_add_equine_species_support.sql:19`); el
  catálogo de etapas admite `BOVINO, BUFALO, BORREGO, EQUIDO` (`029:51`). La 102 trata la especie vacía como `BOVINO`.
* ⚠️ El catálogo de etapas en una base local solo de esquema puede estar vacío: `102_tests.sql` lo siembra con `ON CONFLICT DO NOTHING`.

**(d) Qué hace `sp_procesar_salida_ganado` con TB/BR** (definición vigente: `096_species_scoped_sale_compliance.sql`, sobrecargas de 4 y
5 parámetros; la de 1 parámetro es legada y no la llama el gateway):
* Solo para el régimen bovino (`fn_species_requires_bovine_compliance`: `BOVINO` en cualquier combinación de mayúsculas, o especie
  vacía/desconocida) exige además **arete oficial de 10 dígitos** (`fn_has_official_ear_tag`): sin él devuelve el motivo
  «Sin arete oficial SINIIGA» y **no vende** (`096:132`). Un `S/N-…` nunca cumple.
* TB y BR: si la UPP del animal (`production_unit_id`) tiene un dictamen de hato libre vigente para esa enfermedad
  (`fn_is_herd_free(unidad, 'TB'|'BR')`, `096:137-138`) no se exige la prueba; si no, **rechaza** cuando la fecha es `NULL` o
  `CURRENT_DATE - fecha > 60` (`096:143`, `:146`). El rechazo es de negocio (`success:false` + `motivo`), no una excepción.
* Las demás especies no necesitan arete ni TB/BR.
* Al vender con éxito: `current_status = 'VENDIDO'` y limpia `upp_origen`, `production_unit_id` y `lot_id` (`096:170`), y registra
  `historico_movimientos`.
* La 102 usa la misma regla para los avisos, con la fecha de CDMX (`fn_livestock_chat_today`); la función de salida usa
  `CURRENT_DATE` (hora del servidor). Un caso límite de un día cerca de la medianoche puede divergir; el aviso es informativo.

**Contradicciones con las decisiones:** ninguna que obligue a detenerse. El único punto abierto es la nulabilidad real de
`current_weight_kg` en producción (b), que la 102 protege con una precondición que aborta.

## Orden de despliegue

1. Base de datos: migración 102 (esta). No cambia ningún comportamiento visible.
2. n8n: sin cambios en este PR (el modelo del gateway y su entrada en `spConfigByModel` son el PR 2).
3. Frontend: sin cambios en este PR. El merge a `main` es lo último, solo si 1 está OK.

Los PR 2-4 (gateway/`crud_models`, servicio y pantalla) dependen de que la 102 esté aplicada y verificada.

## Parte 1 — base de datos

Usa una conexión autorizada y guarda la salida de cada paso. Sustituye los placeholders y no pegues credenciales. Ejecuta los
comandos desde la carpeta de las migraciones. **Nada contra producción sin el respaldo (paso 1) y el dry run (paso 4) previos.**

1. **Respaldo previo** (completo):

   ```sh
   pg_dump -Fc -f <RUTA_BACKUP> <BASE_PRODUCCION>
   chmod 600 <RUTA_BACKUP>
   ```

   La 102 no modifica ni reemplaza ninguna función existente; no hay definición previa que guardar aparte.

2. **Estado ANTES:**

   ```sh
   psql <CONEXION_PRODUCCION> -X -v ON_ERROR_STOP=1 -v expect=before -f 102_state_check.sql | tee <RUTA>/102_before.txt
   ```

   Debe terminar en `STATE OK: before`. Si falla por columnas `NOT NULL`, la 099 ausente o una función 102 ya existente, **detente**.

   2b. **Nulabilidad de las columnas (solo lectura)** — ya la imprime el paso anterior en `=== COLUMNS 102 NEEDS TO ACCEPT NULL`;
   todas deben decir `YES`. Si `current_weight_kg` dice `NO`, **detente y reporta** (ver (b)).

3. **Conteo de referencia** (lo imprime `102_state_check.sql` en `=== DATA FINGERPRINTS`; permite verificar que la 102 no modifica
   filas).

4. **Dry run:**

   ```sh
   psql <CONEXION_PRODUCCION> -X -v ON_ERROR_STOP=1 -f 102_panel_livestock_sp.sql
   ```

   Debe imprimir `102: preconditions OK`, `102: OK` y `*** DRY RUN: 102 rolled back ***`. **Detente** si falla una precondición.

5. **Aplicación:**

   ```sh
   psql <CONEXION_PRODUCCION> -X -v ON_ERROR_STOP=1 -v apply=true -f 102_panel_livestock_sp.sql
   ```

   Debe terminar con `*** 102 COMMITTED ***`.

6. **Estado DESPUÉS:**

   ```sh
   psql <CONEXION_PRODUCCION> -X -v ON_ERROR_STOP=1 -v expect=applied -f 102_state_check.sql | tee <RUTA>/102_after.txt
   diff <RUTA>/102_before.txt <RUTA>/102_after.txt
   ```

   Debe reportar `STATE OK: applied`. Del `diff` solo cambian `checked_at_cdmx`, `=== 102 OBJECTS` (aparece la función, con
   `public_revoked = t`) y la línea `STATE`. `=== UNCHANGED FUNCTIONS` y `=== DATA FINGERPRINTS` deben ser **idénticas**, salvo que
   alguien haya capturado o editado un animal entre los pasos 2 y 6.

7. **Humo de solo lectura, empresa 3** (la vista previa no escribe; la transacción es `READ ONLY` y termina en `ROLLBACK`; usa
   `<CORREO_ADMIN_EMPRESA_3>`, un ADMIN activo de la empresa 3, y no lo pegues en el PR):

   ```sql
   BEGIN TRANSACTION READ ONLY;
   SELECT sp_register_livestock_panel(3, NULL, NULL, 'BOVINO', 'VACA', 'CRIA', 'S/N', NULL, NULL, NULL, NULL, NULL,
          NULL, NULL, NULL, 'false', NULL, NULL, '<CORREO_ADMIN_EMPRESA_3>') AS respuesta;
   ROLLBACK;
   ```

   Esperado: `status = 'preview'` (o `need_info` con las opciones si la empresa 3 tiene varias UPP), `preview.sin_arete_oficial = true`,
   un aviso `no_official_tag` que dice que no podrá venderse ni darse de salida, avisos de TB y BR, y un `preview_hash` de 32 hex.
   **No se confirma nada en producción en este PR.** Con un correo ajeno a la empresa debe responder `forbidden`.

8. **Release:** solo si 1-7 están OK, `develop` → `main` con `gh pr merge N --merge`, y confirma que
   `git diff --stat origin/main origin/develop` no imprime diferencias.

### Rollback

1. Antes, retira lo que la llame (PR 2-4 si ya se desplegaron: modelo del gateway y pantalla).
2. `psql <CONEXION_PRODUCCION> -X -v ON_ERROR_STOP=1 -v apply=true -f 102_rollback.sql` (dry run por defecto; **elimina solo** la función
   nueva). Los animales ya registrados con `metadata->>'migration' = '102'` son datos reales y **no se tocan**; se listan con esa
   marca.
3. `102_state_check.sql -v expect=before` debe terminar en `STATE OK: before`.

## Pruebas (LOCAL / base descartable solamente)

`102_tests.sql` (una sola transacción que termina en `ROLLBACK`; aplica la 099 solo si faltan sus ayudantes):

```sh
psql -X -v ON_ERROR_STOP=1 -f 102_tests.sql
```

Cubre: vista previa sin escritura y `preview_hash`; puerta de sesión (sin tenant, no miembro, `CUSTOMER`, palma, actor de otra
empresa que intenta escribir en la 9824, `OWNER` con correo en mayúsculas); UPP única por defecto, varias sin indicar, nombrada, de
otra empresa, empresa sin UPP; lote propio y ajeno; confirmación (todos los campos en su columna, `metadata`, hash inválido, faltante,
datos cambiados, hash de otro actor); duplicados (arete propio, de otra empresa sin nombrarla, chip, animal sin UPP);
`S/N` en seis variantes con aviso, identificador `S/N-9821-…` único, repetido dos veces (`duplicate_recent`, forzado, distintos) y
nunca el literal; bovino sin arete con el aviso de venta; peso opcional y sus inválidos; TB/BR (faltan, 10 días, exactamente 60,
61, otra especie, dictamen de hato libre, fechas futuras o mal escritas); fecha de nacimiento en CDMX con la zona horaria de la
sesión en `Pacific/Kiritimati` y en `UTC`, futura, antigua, mal escrita, nacida en el rancho; fuego repetido (aviso); chip;
protecciones (huella de todas las funciones 099/100, de salida y de palma sin cambios, `PUBLIC` sin `EXECUTE`, sin ayudantes
nuevos); estado `applied`/`before`, idempotencia, rollback dos veces y reaplicación; y, **después del `ROLLBACK`**, un bloque de solo
lectura que prueba que no quedó ningún rastro (empresas, usuarios, animales y la función como antes de correr).
La concurrencia de dos confirmaciones del mismo arete no cabe en una transacción; la respaldan las restricciones `UNIQUE` y el
manejo de `unique_violation` de la función (mismo diseño que `099_concurrency_check.sh`).

## Resultados de la ejecución

**Pendiente.** Ningún SQL de este PR se ha ejecutado. Quien lo ejecute debe pegar aquí (o en el comentario del PR) la salida real:

| Paso | Resultado |
|---|---|
| `102_tests.sql` (base descartable) | _pendiente_ |
| Dry run en producción | _pendiente_ |
| `102_state_check.sql` antes / después, y su `diff` | _pendiente_ |
| Humo de solo lectura, empresa 3 | _pendiente_ |
| `is_nullable` de `current_weight_kg` en producción | _pendiente_ |
