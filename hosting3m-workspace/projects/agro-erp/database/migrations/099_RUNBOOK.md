> ⛔ **NO MERGEAR A `main` HASTA COMPLETAR LAS PARTES 1 Y 2** (base de datos y n8n, verificadas con sus huellas).
> `main` se despliega manualmente: el dueño entra a Plesk y despliega con git. Si el frontend se despliega antes, si se mergea antes, la pantalla nueva falla en producción.

> **Nota de alcance.** Este PR no cambia el frontend (la Parte 3 solo es el merge final). El recuadro aplica igual: los
> agentes nuevos llaman funciones de la 099 y el MCP neutraliza la compra vieja; si los workflows llegaran antes que la base,
> las altas por chat fallarían.

# Runbook 099 — alta por regularización de padrón y compra endurecida por chat

## Alcance

Un animal real que nunca se capturó (estaba en el rancho, o aparece en una guía de tránsito sin alta) se da de alta por Chat
Web o WhatsApp como **regularización**, sin precio, vendedor ni fecha de compra. La compra por chat se endurece. Las dos son
de **dos pasos**: vista previa, "Sí" del usuario y registro con el mismo `preview_hash`.

| Objeto | Qué hace |
|---|---|
| `sp_register_livestock_regularization` (16 parámetros de texto) | Alta con `metadata.source = 'REGULARIZACION_PADRON'`, folio de guía, código de UPP de origen y fecha de nacimiento estimada (edad 0-240 meses). Bovinos: arete oficial de 10 dígitos y folio obligatorios |
| `sp_register_livestock_purchase_chat` (18 parámetros de texto) | Compra: precio mayor que 0, vendedor real (no "desconocido"), UPP resuelta, lote exacto y activo dentro de la UPP. Conserva las llaves que lee la Bitácora |
| 17 funciones `fn_livestock_chat_*` | Sesión (empresa numérica → membresía activa → no palma → ADMIN/OWNER/EDITOR), UPP y lote por coincidencia exacta normalizada, categorías, duplicados y avisos |
| n8n, agentes de Chat y WhatsApp | Dos `postgresTool` conectadas al `AI Agent` de ganadería; empresa, correo y canal salen de la sesión verificada (`.first()`), nunca de `$fromAI`. Prompt: regla D4 y la compra pasa a NIVEL 3 |
| n8n, `v6/MCP Server Cattle` | `register_livestock_purchase` se neutraliza y se renombra a `register_livestock_purchase_obsolete` (responde `status: moved`, no escribe) |

**Respuestas** (`status`): `preview`, `preview_required`, `recorded`, `need_info` (con `issues[]`), `duplicate`,
`duplicate_other_company` (nunca nombra la otra empresa), `exists_without_upp`, `duplicate_recent` (solo animales sin arete;
se fuerza con `force_duplicate = 'true'`), `forbidden`, `palm`, `invalid` y, tras el rollback, `disabled`. Una coincidencia
con `numero_fuego` de la misma empresa es un aviso (`warnings[]`), no un rechazo.

**Códigos** (en el campo `code` de la respuesta): `P0114` UPP no resuelta · `P0115` lote fuera de la UPP · `P0116` arete ya
registrado · `P0117` datos de compra inválidos · `P0118` falta evidencia de regularización · `P0119` reservado. Libres en el
repositorio y en `pg_proc` de producción (2026-11-05).

**Categorías:** BOVINO se valida contra `cattle_lifestage_catalog`. Las demás especies no tienen filas en el catálogo de
producción y usan una lista fija dentro de `fn_livestock_chat_valid_categories`: BORREGO (BORREGA, BORREGO), BUFALO (BUCERRA,
BUCERRO, BUFALA, BUFALO), EQUIDO (CABALLO, CABALLO_CASTRADO, POTRANCA, POTRO, YEGUA). "VAQUILLA" = NOVILLONA.

### Fuera de alcance

* Los 197 bovinos activos de la empresa 5 sin UPP (análisis aparte; ver «Deuda»).
* El becerro de la ejecución #752911 se queda como está (decisión del dueño).
* La ruta del panel web (`crud_models` `cattle_livestock`) sigue sin estas reglas.
* Cambios de frontend.

### Dependencias

* Las dos funciones de herramienta quedan sin `EXECUTE` para `PUBLIC` y sin `GRANT`: dependen de que `n8n_user` sea
  superusuario de PostgreSQL. Si deja de serlo, agrega un `GRANT EXECUTE` explícito.
* `cattle_livestock_rfid_siniiga_key` y `cattle_livestock_electronic_rfid_key` (UNIQUE globales) son la última línea contra un
  arete duplicado en concurrencia; las funciones atrapan el `unique_violation` y responden un `status`.
* La base no puede probar que un humano dijo "Sí": exige el `preview_hash` exacto de la misma empresa, usuario y datos. El
  "Sí" lo exige el prompt.

## Orden de despliegue

1. Base de datos: migración 099.
2. n8n, en la misma ventana y en este orden: MCP, Chat, WhatsApp.
3. Frontend: sin cambios. El merge a `main` es lo último, solo si 1 y 2 están OK.

## Parte 1 — base de datos

Usa una conexión autorizada y guarda la salida de cada paso. Sustituye los placeholders y no pegues credenciales. Ejecuta los
comandos desde la carpeta de las migraciones.

1. **Respaldo previo:**

   ```sh
   pg_dump -Fc -f <RUTA_BACKUP> <BASE_PRODUCCION>
   ```

2. **Estado ANTES:**

   ```sh
   psql <CONEXION_PRODUCCION> -X -v ON_ERROR_STOP=1 -v expect=before -f 099_state_check.sql | tee <RUTA>/099_before.txt
   ```

   Debe terminar en `STATE OK: before`. Comprueba en la salida que `fn_reject_palm_company` es `ccf38f121f647bedcb152dd02552f669`
   (el script falla si no lo es) y que existen las dos llaves UNIQUE y `cattle_livestock_category_check`.

3. **Dry run:**

   ```sh
   psql <CONEXION_PRODUCCION> -X -v ON_ERROR_STOP=1 -f 099_livestock_regularization.sql
   ```

   Debe imprimir `099: preconditions OK; fn_reject_palm_company md5 ccf38f12…`, `099: OK` y `*** DRY RUN: 099 rolled back ***`.
   **Detente** si falla una precondición: falta una columna o llave, una categoría fija no está en el CHECK, o una función de la
   099 ya existe con otra firma.

4. **Aplicación:**

   ```sh
   psql <CONEXION_PRODUCCION> -X -v ON_ERROR_STOP=1 -v apply=true -f 099_livestock_regularization.sql
   ```

   Debe terminar con `*** 099 COMMITTED ***`.

5. **Estado DESPUÉS:**

   ```sh
   psql <CONEXION_PRODUCCION> -X -v ON_ERROR_STOP=1 -v expect=applied -f 099_state_check.sql | tee <RUTA>/099_after.txt
   diff <RUTA>/099_before.txt <RUTA>/099_after.txt
   ```

   Debe reportar `STATE OK: applied`. Del `diff` solo cambian `checked_at_cdmx` y la sección `=== 099 OBJECTS` (19 funciones;
   las dos `sp_*` con `public_revoked = t`). `=== UNCHANGED FUNCTIONS` debe ser idéntica. Las `=== DATA FINGERPRINTS` deben ser
   idénticas salvo que alguien haya capturado o editado un animal entre los pasos 2 y 5: si cambian, compara los conteos por
   `source` antes de concluir.

6. **Humo de solo lectura, empresa 3** (la vista previa no escribe; la transacción es `READ ONLY` y termina en `ROLLBACK`).
   `<CORREO_ADMIN_EMPRESA_3>` es un ADMIN activo de la empresa 3; no lo pegues en el PR:

   ```sql
   BEGIN TRANSACTION READ ONLY;
   -- La empresa 3 tiene cuatro UPP: sin nombre debe responder need_info con el issue 'upp' ambiguous (P0114) y 4 opciones.
   SELECT sp_register_livestock_regularization('3', '<CORREO_ADMIN_EMPRESA_3>', 'CHAT_WEB', NULL, NULL, 'BOVINO', 'BECERRO',
          'CRIA', '8', '9909900001', 'PRUEBA-099', NULL, NULL, 'false', NULL, NULL)->'issues';
   -- Precio 0 y vendedor "desconocido": need_info con dos issues P0117.
   SELECT sp_register_livestock_purchase_chat('3', '<CORREO_ADMIN_EMPRESA_3>', 'CHAT_WEB', NULL, NULL, 'BOVINO', 'BECERRA',
          'CRIA', NULL, NULL, NULL, '0', 'desconocido', NULL, NULL, 'false', NULL, NULL)->'issues';
   ROLLBACK;
   ```

   Si la primera consulta responde algo distinto de `need_info`, o la transacción reporta un intento de escritura, detente.

## Parte 2 — workflows de n8n

**Precondiciones:** Parte 1 completa; el PR está mergeado a `develop` y la CI está en verde. No uses `n8n import:workflow`
(desactiva el workflow y cambia el `versionId`). Nunca pruebes desde el panel de prueba de un nodo ni desde el chat del editor:
corren contra la base de producción sin pasar por la resolución de sesión (Reglas 6 y 11 del `CLAUDE.md` de agro-erp).

1. **Respaldos.** En producción, abre cada workflow, **⋯ → Download** y guarda el archivo fuera del repositorio con permisos
   `600`: `v6/MCP Server Cattle`, `v6/ai/chat cattle` y `v6/WhatsApp Agent Catlte`.

2. **Comparación con `origin/main`.** Por cada workflow, corre el snippet de comparación del `CLAUDE.md` raíz (sección
   «Runbook de despliegue de workflows en n8n 2.x», paso 3) entre el respaldo y el JSON de `origin/main`. Resultado esperado:
   `No differences.` Complementa con `python3 -I ~/node_fingerprints.py` **en el VPS** (el script vive ahí, no en el equipo de
   desarrollo; copia al VPS el JSON de `origin/main`, verifica su checksum y deja los dos archivos con permisos `600`), corrido
   **sobre los dos archivos** (respaldo y `origin/main`), y compara estos nodos:

   | Workflow | Nodos |
   |---|---|
   | `v6/MCP Server Cattle` | `register_livestock_purchase` (y el resto del workflow sin diferencias) |
   | `v6/ai/chat cattle` | `AI Agent`, `Resolver Empresa Chat`, `Validar Token`, `MCP Cattle Management` |
   | `v6/WhatsApp Agent Catlte` | `AI Agent`, `Resolver Tenant`, `Get User Role`, `Set Role`, `MCP Client` |

   **Si hay cualquier diferencia, detente:** producción puede traer cambios manuales (caso del 2026-10-24). Primero se
   incorporan a `main` y se regenera este PR; solo después se importa. Referencia del repositorio (md5 de `parameters` con llaves
   ordenadas, primeros 8; **no** es la salida de `~/node_fingerprints.py`, no los compares con ella):

   | Workflow | Nodo | `origin/main` | candidato (`develop`) |
   |---|---|---|---|
   | MCP | `register_livestock_purchase` → `register_livestock_purchase_obsolete` | `27f7724c` | `7da9b432` |
   | Chat | `AI Agent` | `24b23613` | `9fd36902` |
   | Chat | `register_livestock_regularization` (nuevo) | — | `ddc802be` |
   | Chat | `register_livestock_purchase` (nuevo) | — | `73e77ad6` |
   | Chat | `Resolver Empresa Chat` / `MCP Cattle Management` | `d1bd1ffb` / `e43cd600` | sin cambio |
   | WhatsApp | `AI Agent` | `2123a894` | `88a3985f` |
   | WhatsApp | `register_livestock_regularization` (nuevo) | — | `95b15afb` |
   | WhatsApp | `register_livestock_purchase` (nuevo) | — | `850c2c47` |
   | WhatsApp | `Resolver Tenant` / `Get User Role` / `Set Role` / `MCP Client` | `f774ebf6` / `ea4d5819` / `a043a38b` / `e43cd600` | sin cambio |

3. **Comparación con `origin/develop`.** Repite el snippet contra el JSON de `origin/develop`. Debe listar **exactamente**:
   * MCP: los nodos `register_livestock_purchase` (sale) y `register_livestock_purchase_obsolete` (entra), y la conexión
     renombrada.
   * Chat y WhatsApp: `AI Agent` (solo `systemMessage`), `register_livestock_regularization` y `register_livestock_purchase`
     (nuevos), y sus dos conexiones `ai_tool` hacia `AI Agent`.

   Confirma también que `credentials`, `webhookId`, `typeVersion` y `settings` no cambian. Los `id` de nodo no son significativos.

4. **Importación — orden OBLIGATORIO y en la misma ventana: MCP, Chat, WhatsApp.** En cada uno: **⋯ → Import from file…**,
   elige el JSON de `develop`, **Save** y **Publish**.
   * **Por qué este orden:** el cliente MCP de cada agente expone todas las tools del servidor. Si un agente nuevo se publica
     mientras el MCP viejo todavía expone `register_livestock_purchase`, el agente tendría dos herramientas con ese nombre y
     OpenAI rechazaría la llamada. El MCP va primero.
   * Entre el MCP y el último agente, una compra pedida a un agente todavía sin importar responde "moved" y no escribe nada:
     mantén la ventana en minutos.
   * Confirma que el nombre y el estado publicado de cada workflow no cambiaron al importar.

5. **Verificación de publicación.** Descarga otra vez los tres workflows y compara cada uno con el JSON de `develop` (mismo
   snippet): debe dar `No differences.` y las huellas de `~/node_fingerprints.py` (en el VPS) deben coincidir con las del JSON
   de `develop`.
   **No se considera desplegado hasta que coincidan** (en v1.18.1 una importación quedó guardada sin publicar).

## Prueba en producción — solo empresa 3, por el canal real (Chat Web y WhatsApp)

Usa un ADMIN de la empresa 3. En WhatsApp, su teléfono debe estar ligado a la empresa 3 y la selección guardada debe ser la
empresa 3 (consulta de solo lectura en `workflows/09-MCP-Agent-Cattle/v6/repro-phase5/REPRO_QA_SCRIPT.md`, «Antes de
empezar», punto 4). Nunca uses otra empresa ni aretes
reales. Aretes ficticios con prefijo `99` (ningún estado INEGI usa `99`); comprueba antes que no existan:

```sql
BEGIN TRANSACTION READ ONLY;
SELECT rfid_siniiga FROM cattle_livestock WHERE rfid_siniiga IN ('9909900001', '9909900002');   -- debe devolver 0 filas
ROLLBACK;
```

Guarda el id de cada ejecución de n8n.

1. **Regularización con varias UPP, vista previa y Sí (Chat Web).** Escribe: «Tengo un becerro que no está en el sistema, no lo
   compramos; arete 9909900001, guía PRUEBA-099, unos 8 meses, de cría». Esperado:
   * el agente usa `register_livestock_regularization`, no la compra, y no pregunta precio ni vendedor;
   * pide la UPP con las cuatro opciones de la empresa 3 (respuesta `need_info`, `upp` ambiguous): «QA FIFO UPP (pruebas)»
     `99-097-9997-001`, «UPP Testing» `99-999-9999-999`, «QA5R2 UPP Norte» `99-502-0001-001` y «QA5R2 UPP Sur»
     `99-502-0002-001`; contesta con «UPP Testing»;
   * la vista previa debe mostrar la UPP «UPP Testing» con código `99-999-9999-999`;
   * muestra la vista previa con empresa y UPP tal como las devolvió la herramienta y pregunta «¿Confirmas…? (Sí/No)»;
   * con «Sí» responde que quedó registrado (`recorded`).
   Verifica (solo lectura):

   ```sql
   BEGIN TRANSACTION READ ONLY;
   SELECT cl.tenant_id, cl.category, cl.business_model, cl.birth_date, pu.upp_code,
          cl.metadata->>'source' AS source, cl.metadata->>'guide_folio' AS folio, cl.metadata->>'channel' AS channel
     FROM cattle_livestock cl LEFT JOIN production_units pu ON pu.id = cl.production_unit_id
    WHERE cl.rfid_siniiga = '9909900001';
   ROLLBACK;
   ```

   Esperado: `3`, `BECERRO`, `CRIA`, fecha estimada (hoy − 244 días), `99-999-9999-999`, `REGULARIZACION_PADRON`,
   `PRUEBA-099`, `CHAT_WEB`.

2. **Duplicado de arete (Chat Web).** Repite el mensaje del paso 1. Esperado: respuesta `duplicate` relatada literal, sin vista
   previa ni registro.

3. **Compra con precio 0 (Chat Web).** «Compré una becerra en 0 pesos a desconocido, de cría». Esperado: `need_info` con los
   mensajes de precio y vendedor (P0117), sin vista previa y sin registro. El agente no debe ofrecer inventar los datos; si dice
   que no se compró, debe pasar a la regularización.

4. **WhatsApp.** Repite los pasos 1 a 3 con el arete `9909900002` (texto, no audio). En el paso 1 la vista previa debe nombrar
   la empresa (regla «EMPRESA EN WHATSAPP»). Verifica la fila con la consulta del paso 1 (`channel = WHATSAPP`).

5. **Si el agente se equivoca** (inventa precio o vendedor, registra sin vista previa, oculta un `need_info` o un duplicado,
   manda `force_duplicate` sin `duplicate_recent`), regístralo como hallazgo con el id de la ejecución y aplica el rollback de
   n8n si el error escribe datos falsos.

**Datos de prueba:** los dos animales de prueba (`9909900001` y `9909900002`) **se quedan en la empresa 3**. Para la limpieza
lógica futura se identifican por `metadata.source = 'REGULARIZACION_PADRON'` y `tenant_id = 3` (además, `metadata.migration =
'099'` y el arete con prefijo `99`). Esa limpieza será borrado lógico (`BAJA_DEPURACION_DATOS`) con un script propio, dry run y
respaldo, solo sobre esas filas. Nunca `DELETE`.

## Parte 3 — frontend

Sin cambios. **Solo si las Partes 1 y 2 y la prueba están OK:** publica `develop` → `main` (`gh pr merge N --merge`) y
confirma que `git diff --stat origin/main origin/develop` no imprime nada.

## Plan B — rollback

1. **n8n primero, en orden inverso: WhatsApp, Chat, MCP.** En cada uno, **⋯ → Import from file…** con el respaldo del paso 1
   de la Parte 2, **Save** y **Publish**; después descarga y compara con el respaldo (`No differences.`). Orden inverso por la
   misma razón: si el MCP viejo volviera mientras un agente nuevo sigue publicado, `register_livestock_purchase` quedaría
   duplicado.
2. **Base de datos después:**

   ```sh
   psql <CONEXION_PRODUCCION> -X -v ON_ERROR_STOP=1 -f 099_rollback.sql                  # dry run
   psql <CONEXION_PRODUCCION> -X -v ON_ERROR_STOP=1 -v apply=true -f 099_rollback.sql
   psql <CONEXION_PRODUCCION> -X -v ON_ERROR_STOP=1 -v expect=rolled_back -f 099_state_check.sql
   ```

   Sin `DROP` ni `DELETE`: las dos funciones de herramienta conservan su firma y responden `{"status":"disabled"}`; las
   auxiliares quedan; **los animales ya registrados no se tocan** (se listan con `metadata->>'migration' = '099'`). Debe
   reportar `STATE OK: rolled_back`. Volver a aplicar la 099 restaura las herramientas.

## Pruebas de ensayo (solo LOCAL o copia descartable)

Resultados del 2026-11-05 en la copia `hosting3m_schema` (PG 16.15, sin datos):

* `099_tests.sql`: **64 aserciones**, una transacción con `ROLLBACK` (aplica la 099, su rollback dos veces y la 099 otra vez).
  **Nunca en producción.**
* `099_mutation_check.sh`: control M0 OK y **14 de 14 mutaciones detectadas**, cada una en su prueba (UPP de otra empresa, lote
  fuera de la UPP, precio 0, marcadores de vendedor, vista previa que escribe, membresía, palma, aretes de otras empresas,
  commit sin `preview_hash`, CUSTOMER, BUFALO con NOVILLO, `numero_fuego` como rechazo, edad sin tope, arete bovino).
* `099_concurrency_check.sh`: **3 de 3 escenarios**. Mismo arete en la misma empresa → la segunda sesión esperó unos 3.7 s y
  respondió `duplicate`. Compra en A contra regularización en B → `duplicate_other_company` sin nombrar A. Primera sesión con
  ROLLBACK → la segunda registró. **Confirma datos** (empresas 9897/9898) y los borra al terminar; necesita la 099 aplicada y
  confirmada en una copia sin animales. Después de usarla, deja la copia limpia **recreándola desde el dump**, no con `DROP`.
* `099_state_check.sql`: `before`, `applied` y `rolled_back` OK.
* Las expresiones de las cuatro `postgresTool` nuevas se validaron con Node.js: elementos = parámetros (16 y 18); sin sesión,
  empresa y correo quedan en `null` y la base responde `forbidden`.

Antes de importar en producción, conviene una conversación completa por canal en el n8n LOCAL (cambia la URL del cliente MCP
a `http://localhost:5678/mcp/v6/cattle-management` sin versionar ese cambio y desactiva el SMTP de notificaciones).

## Deuda (no se resuelve en la 099)

* ✅ **Nota corregida — `crud_models` `cattle_livestock` tiene `DELETE` en `allowed_ops`, pero el Meta-CRUD no borra
  físicamente** (`{SELECT,INSERT,UPDATE,DELETE,GETONE,GETALL}`, insert/update ADMIN y EDITOR; producción 2026-11-05). Esta
  viñeta decía antes que el panel permitía un `DELETE` físico; es incorrecto. Verificado en producción y en `v6/CRUD` (nodo
  `Build Query`, caso `delete`): el gateway ejecuta `UPDATE <tabla> SET is_active = false WHERE <pk> = …`, es decir, una baja
  lógica. `cattle_livestock` **no tiene columna `is_active`**, así que un `delete` sobre este modelo falla con un error de SQL y
  no modifica ni borra nada. **Deja de ser deuda prioritaria.**
  * Habilitar `DELETE` en `allowed_ops` de un modelo cuya tabla no tiene `is_active` es una configuración sin efecto (la
    operación siempre falla).
  * Si en el futuro se añadiera `is_active` a `cattle_livestock`, un `delete` dejaría al animal «desactivado» pero con
    `current_status` en `ACTIVO`, sin pasar por `BAJA_DEPURACION_DATOS`. No añadir esa columna sin revisar este punto.
* La Bitácora (`vw_cattle_event_log`) no muestra las altas `REGULARIZACION_PADRON` (solo la rama `COMPRA`).
* La memoria del agente de ganadería en WhatsApp usa solo el teléfono como llave: puede mezclar el contexto de dos empresas.
  Mitigado para las altas por el `preview_hash`, que ata empresa y usuario.
* `Guardar Pregunta Pendiente` (WhatsApp) pasa el texto como parámetros separados por comas: un mensaje con comas se parte.
* 197 bovinos activos de la empresa 5 sin UPP, sin lote, sin terreno rentado y con `source` NULL. Sin UPP, la venta no consulta
  el Hato Libre (la UPP de la empresa 5 no tiene dictamen vigente) y no se pueden prestar a repasto (`P0100`). Análisis aparte.
* 1 animal BUFALO con categoría NOVILLO en producción (calidad de datos).
* El catálogo de etapas solo tiene BOVINO; las demás especies usan una lista fija en la 099.
* La ruta de alta del panel web no tiene las validaciones de la 099.
