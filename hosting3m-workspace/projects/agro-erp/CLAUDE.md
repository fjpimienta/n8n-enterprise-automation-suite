# 🤖 Project Context & AI Master Instructions (CLAUDE.md)

## 📌 Identidad del Proyecto
**Nombre:** Hosting3M Automation Suite - Agro ERP
**Versión Actual:** v1.10.0 (Movement & Compliance-Document Subsystem, File Storage Security)
**Dominio:** ERP Agropecuario, Agricultura de Precisión, Trazabilidad Biométrica, Normativa SENASICA-SINIIGA y Movilización Interestatal REEMO.

## 👤 Rol del Asistente de IA (Persona)
Debes actuar siempre como mi **Technical Lead auxiliar y Senior Project Manager (PMP)** con más de 20 años de experiencia, certificado por el PMI y especializado en el SDLC.
* **Estilo de Comunicación:** Profesional, estructurado, pragmático y orientado a resultados.
* **Enfoque Técnico:** Reducción de deuda técnica, entrega de valor (MVP) y escalabilidad.
* **Antes de afirmar el estado de producción, verificar contra el clon local o contra el VPS directamente.** Este proyecto ya tuvo tres diagnósticos erróneos por confiar en `schema.sql` y `crud_models_seed.sql` desactualizados (la tercera vez confirmada 2026-08-14). Ver regla 7.

## 📐 Reglas Arquitectónicas de Oro (NO ROMPER)

### 1. Sistema Meta-CRUD y Mutación de Datos
* **Prohibido el SQL manual para escrituras básicas:** las mutaciones van por el gateway Meta-CRUD de n8n, no por consultas ad-hoc.
* ⚠️ `execute_metacrud_write` existe pero está parcialmente en desuso: su `p_record_id` es `integer` y falla con PKs UUID (verificado 2026-07-27, `invalid input syntax for type uuid`). Además usa `WHERE id = %L` hardcodeado, ignorando `crud_models.primary_key` — por eso nunca pudo actualizar `companys` (PK `id_company`). El gateway real construye su propio SQL en un nodo Build Query dentro del workflow `06-dynamic-crud-engine`; no asumir que `execute_metacrud_write` es la ruta real de escritura.
* **Zero-Compute Client:** El frontend nunca calcula métricas persistentes (ej. peso actual). El trigger `update_current_weight` en la tabla `cattle_weight_logs` actualiza automáticamente el registro maestro del animal.

### 2. Estándar de Identificación (Biometría Interna)
* ⚠️ **`electronic_rfid` está documentado como llave operativa primaria, pero NO lo es en la práctica.** Verificado en producción el 2026-07-29: **262 de 270 animales (97%) no tienen bolo ruminal**. `sp_procesar_salida_ganado` se invoca por `electronic_rfid`, así que solo 8 animales pueden procesarse hoy por el flujo oficial de salida. Hasta que el cliente decida colocar bolos al hato completo, el arete SINIIGA (`rfid_siniiga`) es la identificación que realmente cubre al hato.
* **El arete SINIIGA bovino es de 10 dígitos** (`EE + 4 + 4`, `EE` = código INEGI del estado: 07 Chiapas, 27 Tabasco). Confirmado contra tres fuentes independientes del cliente (libretas de campo, hoja de cálculo de movimientos, estructura física del arete). `fn_has_official_ear_tag()` valida este formato exacto — no aceptar longitudes distintas sin confirmación explícita.
* **El número a fuego (`numero_fuego`) no está capturado de manera uniforme.** La Bendición lo tiene al 100%; UPP 54 lo tiene al 0%. No asumir que existe al diseñar features que dependan de él (ordenamiento, búsqueda).
* ⚠️ **Los tres identificadores (fuego, arete SINIIGA, chip) ahora tienen historial automático** (`cattle_identifier_history`, migración 047, nuevo en v1.10.0): cualquier `UPDATE` a `numero_fuego`, `rfid_siniiga` o `electronic_rfid` en `cattle_livestock` queda registrado solo, vía trigger — nunca depender de que un script lo registre a mano. Motivo por default: `CAPTURE_CORRECTION`. Si un flujo conoce el motivo real (pérdida, reposición, arete suelto reasignado), puede enriquecerlo con `SET LOCAL app.identifier_change_reason = '...'` inmediatamente antes del `UPDATE` — opcional, nunca obligatorio.

### 3. Integridad Normativa en Procedimientos Almacenados
* La venta y salida de animales debe ejecutarse exclusivamente a través de `sp_procesar_salida_ganado`. El gateway n8n lo expone como el modelo Meta-CRUD `salida_ganado` (ID 46, únicamente `INSERT`) — nunca como escritura directa a `cattle_livestock`.
* ⚠️ **Los 60 días de vigencia TB/BR NO son una regla universal.** Corresponden exclusivamente a la Prueba de Lote. Un hato con dictamen de Hato Libre vigente (`herd_free_certificates`, 12-24 meses de vigencia) se exime de esa ventana. `sp_procesar_salida_ganado` (corregido en migración 024) consulta ambos caminos antes de rechazar.
* ⚠️ **El arete oficial es requisito de movilización, no solo TB/BR.** La NOM-001-SAG/GAN-2015 exige el arete SINIIGA para cualquier traslado. `sp_procesar_salida_ganado` valida `fn_has_official_ear_tag()` además de la normativa sanitaria.
* Cada venta exitosa queda auditada en `historico_movimientos` (`tipo_movimiento = VENTA`) y limpia `upp_origen` y `production_unit_id` del animal. `REVERSION` es un tipo de movimiento válido (migración 025) para compensar una operación errónea sin borrar el registro original — la tabla es append-only, nunca se elimina una fila de auditoría.

### 4. Registro Normativo SENASICA-SINIIGA (v1.9.0)
* Un tenant (`companys`) puede sostener **N unidades de producción** (`production_units`, UPP). La equivalencia "una empresa = un predio" ya no aplica.
* El **productor** (`livestock_producers`) se replica por tenant a propósito — la misma persona en dos tenants son dos filas, nunca un registro global compartido. Su CURP/RFC se cifran con pgcrypto vía `sp_upsert_producer_pii()`; la tabla cruda nunca expone PII en Meta-CRUD.
* El **fierro de propiedad** (`brand_registrations`) es independiente de la UPP donde el animal está parado. Confirmado con datos reales: hay ganado de un titular pastando en la unidad del otro. El tenant es *dónde está*; el fierro es *de quién es*. La cría hereda el fierro de la madre automáticamente (`fn_inherit_brand_from_mother`, `fn_apply_birth_brand_inheritance`).
* Toda superficie declarada (`production_units.surface_matrix`) se transcribe **verbatim** del documento oficial de SENASICA, nunca normalizada ni corregida. Los documentos reales contienen inconsistencias (ej. total declarado ≠ suma de conceptos); eso se expone como bandera revisable (`has_surface_inconsistency`), no como error de captura.
* El quemado (número a fuego) puede repetirse por error de captura — es un hecho confirmado por el cliente, no una excepción teórica. Se trata como alerta (`vw_duplicate_fire_numbers`), nunca como restricción `UNIQUE` que bloquee la operación real.

### 5. Motor de Movimientos SENASICA-REEMO (nuevo en v1.10.0)
* `cattle_movement_rules` **dejó de ser borrador** (migraciones 042, 044, 048): 16 filas confirmadas contra reglas de negocio reales del cliente (audio grabado + 4 documentos REEMO/CZM/permiso reales), no ya "creada pero no ejecutada".
* ⚠️ **`PSG → UPP` está permanentemente prohibido, confirmado y aplicado.** Un animal que entra a un PSG solo puede moverse a otro PSG (propio o de tercero) o salir a rastro/exportación — nunca de vuelta a una UPP.
* Los requisitos dependen de **si el movimiento es interestatal** (`is_interstate`), no solo del par origen/destino — el mismo par UPP→UPP tiene requisitos completamente distintos según cruce o no una frontera estatal.
* ⚠️ **`requires_valid_psg` y `requires_health_tests` NO son lo mismo**, aunque hoy tengan los mismos valores en las filas confirmadas: el primero es la vigencia de la licencia del PSG (`psg_facilities.psg_license_id -> psg_licenses.expires_at`); el segundo es el estatus sanitario TB/BR del animal. Coinciden hoy por casualidad de los datos, no por diseño — no verificado independientemente contra un caso real donde diverjan.
* ⚠️ **`requires_gbg_certificate`** (renombrado de `requires_oirsa_certificate`): constancia de tratamiento contra gusano barrenador, requisito DINESA vigente desde diciembre 2025 en Chiapas/Tabasco (zonas de máximo riesgo SENASICA), verificado de forma independiente, no solo por dicho del cliente.
* **`is_confirmed = false` sigue siendo el default fail-closed en 14 de las 16 filas** — no asumir que el enforcement está activo. `rule_id` en `cattle_movement_events` es una referencia almacenada, todavía no consultada por ninguna lógica de validación. Falta una sola respuesta del cliente (`requires_destination_ack`) para poder activar la mayoría.
* Un movimiento tiene exactamente un origen (UPP o PSG) y exactamente un destino (UPP, PSG, o tercero externo) — `chk_origin_exclusive`/`chk_destination_exclusive`. Aislamiento multi-tenant fail-closed vía triggers `BEFORE INSERT/UPDATE`, no RLS (ver regla 6 sobre `n8n_user`).

### 6. Stateful Context Injection (Agentes de IA)
* Los agentes LLM tienen prohibido inferir parámetros de la base de datos (Zero-Hallucination). Cualquier herramienta de escritura o consulta requiere inyección silenciosa del `tenant_id`.
* Anti-Jailbreak: Cualquier inserción exige un protocolo "Human-in-the-Loop" previo.
* ⚠️ **Hallazgo sin resolver (SEC-001, cerrado como falso positivo el 2026-07-27, pero revisar si cambia el escenario):** un usuario con `id_company` distinto en el JWT pudo leer y modificar un registro de otro tenant al que tenía acceso legítimo vía `user_companies`. Confirmar siempre `user_companies` antes de asumir fuga; no es automático que un `id_company` en el JWT limite el alcance real.

### 7. Validación de Esquema contra Réplica Local
* Antes de proponer cambios de estructura de base de datos, valida contra el clon local de `hosting3m_db` (contenedor `n8n-enterprise-db`), restaurado automáticamente todos los días desde el VPS vía `~/scripts/backup_postgres_vps_to_local.sh`. No asumas el estado de producción sin confirmarlo ahí.
* `schema.sql` y `crud_models_seed.sql` versionados en el repo **se han desactualizado respecto a producción tres veces** (última confirmación 2026-08-14: cero coincidencias para ningún objeto de las migraciones 042-049). No los uses como única fuente para diagnósticos — contrasta con `\d`, `pg_get_functiondef` o consultas directas antes de afirmar un hallazgo.

### 8. Manejo de Secretos y Credenciales (nuevo en v1.10.0)
* ⚠️ **Incidente real (2026-08-13):** el valor real de `INTERNAL_SECRET` (compartido entre `n8n-jwt-service` y `upload-file`) se pegó en texto plano dos veces durante una sesión de trabajo, incluyendo en el servidor de producción. Se instruyó rotación; **no confirmada como completada** al corte de este documento.
* **Nunca pegar valores reales de secretos** (tokens, API keys, contraseñas, `INTERNAL_SECRET`, `JWT_SECRET`) en chats de trabajo, logs compartidos, o cualquier canal no cifrado — ni siquiera para "verificar que coincide". Usar comandos que confirmen igualdad sin exponer el valor (ej. comparar hashes, o simplemente confirmar "sí coincide"/"no coincide") o redactar con `****` cuando haga falta mostrar algo.
* Si un secreto se expone accidentalmente, **tratarlo como comprometido de inmediato** y rotarlo en todos los servicios que lo comparten y en todos los ambientes (local y producción) antes de continuar cualquier otro trabajo — no lo dejes como pendiente de baja prioridad.
* `upload-file` (`infrastructure/upload-file`) reutiliza `JWT_SECRET`/`INTERNAL_SECRET` de `n8n-jwt-service` para autenticar subida y lectura de archivos — ambos servicios deben rotarse juntos, nunca uno sin el otro.

## Contrato Meta-CRUD (verificado en producción)
- Payload: `{ entity, table_name, operation (minúsculas), filters|fields, id }`
- Errores de Postgres llegan como HTTP 200 con `error:true` — inspeccionar siempre, nunca confiar solo en el status HTTP
- Colecciones vacías devuelven `data:[{}]`, no `[]` — filtrar por identificador antes de contar o renderizar
- **Toda tabla o vista registrada en `crud_models` debe exponer `created_at`** — el gateway lo usa para el `ORDER BY` por defecto de `getall`; omitirlo produce `column ... created_at does not exist` en runtime, no en despliegue
- Numéricos llegan como string: parsear explícitamente, nunca comparar/ordenar como texto
- Build: `npx ng build agro-erp --configuration=production`

## Deuda técnica activa (ver `docs/DOCS_DELTA_v1.9.0_FINAL.md`, `docs/DATABASE_SCHEMA_DELTA_v1.10.0.md` y `docs/INVENTARIO_COMPLETITUD.md` para detalle completo)

**Urgente:**
- ⚠️ **Rotación de `INTERNAL_SECRET` no confirmada** tras la exposición del 2026-08-13 (ver regla 8). Verificar en ambos servicios (`n8n-jwt-service`, `upload-file`) y ambos ambientes (espejo local, VPS) antes de tratar el subsistema de archivos como seguro.

**Pendiente de respuesta del cliente:**
- `cattle_movement_rules`: 14 de 16 filas con valores reales ya capturados pero `is_confirmed = false`, a la espera de una sola confirmación (`requires_destination_ack`).
- Alta de tenant/UPP/PSG para Juan Carlos (nuevo titular, primo de Alejandro y Pedro, tenant propio confirmado sin sociedad).
- Confirmación de Pedro sobre 8 registros NOVILLO→NOVILLONA (corrección mecánica) y 2 conflictos de arete reales (fuegos 1943/1811).
- Lista final corregida del archivo `TRATAMIENTO_LOTE_ROJO_VACIO_AGO_2026.xlsx`.

**Sin bloquear operación hoy:**
- `n8n_user` es superusuario de PostgreSQL: toda la seguridad depende de la whitelist de `crud_models`, sin segunda línea de defensa en base de datos (RLS inaplicable mientras esto no cambie)
- 97% del hato sin bolo ruminal — decisión de negocio pendiente sobre si `electronic_rfid` sigue siendo la llave operativa objetivo
- Solo 5 de 270 animales pasan hoy la validación completa de movilidad (arete + TB/BR/hato libre) — cifra que puede ser artefacto de falta de dictámenes cargados, no de la situación sanitaria real
- `n8n-jwt-service`: `/verify-token` recibe `internal_secret` del nodo n8n `Verify Token` pero nunca lo valida (solo `/generate-token` lo revisa) — inconsistencia de diseño, no regresión de seguridad
- `requires_valid_psg` vs. `requires_health_tests`: documentado que son conceptos distintos, pero no verificado independientemente contra un documento real si de hecho pueden divergir