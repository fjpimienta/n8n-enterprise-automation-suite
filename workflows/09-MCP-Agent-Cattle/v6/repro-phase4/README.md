# Reproducción fase 4 (partos, servicios, historial de la hembra) — tools de `v6/MCP Server Cattle` (migraciones 087 y 088)

Archivo importable: `repro_phase4_tools.json` (8 nodos `postgresTool` + conexión `ai_tool` hacia `MCP Server Cattle`).

**Cómo cargarlas (después de aplicar la 087 y la 088; `get_dam_reproductive_history` necesita la 088, las otras 7 la 087):** abrir `v6/MCP Server Cattle` en el editor → pegar el contenido del JSON en el lienzo (Ctrl+V) → comprobar que cada tool quedó conectada a `MCP Server Cattle` → guardar → **Publish** → descargar el export y comprobar la huella. Antes de importar, comparar producción contra `main` por huella (puede traer cambios manuales).

⚠️ Las tools **no se ven para el agente** hasta que se agreguen a los dos *System Prompt* (Fase 5). Hasta entonces quedan inertes. El orden base de datos → n8n evita errores `function does not exist`.

⚠️ **No se modifican** las tools existentes (`register_birth_event`, `log_breeding_event`, `void_event`, `log_palpation_event`...). Pero **su comportamiento ya cambia** con las migraciones porque llaman a procedimientos reemplazados con la misma firma:

* `register_birth_event` (→ `sp_register_birth_event`, 087): el correo ya se valida contra la membresía; un reintento exacto regresa `duplicate_skipped`; guarda quién lo reportó; y, con la 088, regresa `service_link`. Sigue registrando una cría huérfana (con advertencia) si la madre es ambigua: la ambigüedad y el aviso de parto duplicado viven solo en `register_birth_checked`.
* `log_breeding_event` (→ `sp_log_breeding_event`, 088): ahora puede responder **`{"success": false, "status": "ambiguous" | "rejected"}`** (semental ambiguo, que no es toro, o la misma hembra) **sin ser un error SQL**, más `warnings` (`sire_not_resolved`, `semen_batch_missing`) y `duplicate_skipped`. La descripción actual de la tool solo habla de errores: el prompt de la Fase 5 debe decirle al agente que relaye `message` y `candidates` cuando `success` sea false y que muestre los `warnings`.
* `void_event` (→ `sp_void_event`, 088): un servicio ligado a un parto responde **`{"success": false, "status": "rejected", "code": "LINKED_TO_BIRTH", "birth_event_id": ...}`** (no es un error SQL): el agente debe decir que no se anuló.

⚠️ **No hay tool para cambiar la ventana de posible duplicado** (`sp_repro_births_set_config`, solo ADMIN): el agente solo la lee (`get_births_config`).

⚠️ **Las tools de escritura** (`register_birth_checked`, `births_batch_register`, `register_historical_birth`, `void_historical_birth`) exigen en su descripción el Sí/No del usuario antes de llamarlas. Es una regla de prompt (como en el resto del agente), no una garantía criptográfica; debe repetirse en los dos *System Prompt* en la Fase 5.

Credencial: `Postgres account`. `tenant_id` y `user_email` siguen siendo `$fromAI` como en las demás tools de ganadería (deuda conocida, Regla 6); la base los valida de todos modos (`fn_repro_ctx`: membresía activa + empresa que no es de palma, falla con error).

Los parámetros opcionales están declarados `'string'` (no `'number'`) porque la query los castea con `$n::text` (Regla 15 del `CLAUDE.md` de agro-erp).

## `register_birth_checked`

- **Description (manual):** Registra UN parto con validación completa: crea la cría, liga la madre y, si la madre estaba PREÑADA, la pasa a VACÍA (misma lógica que register_birth_event, que es el escritor). Identifica a la madre por su arete SINIIGA/RFID o número a fuego tal como el usuario lo dio (dam_identifier) o por su id (dam_id). 🛑 NUNCA elijas entre varios animales: si regresa status 'ambiguous', muestra los 'candidates' (arete, fuego, categoría, estatus) y pide cuál; no se registró nada. 'not_found' = esa madre no existe en la empresa. 'invalid' trae un 'code' y un 'message' (sexo, fecha, peso, madre vendida o muerta, madre que no es hembra, lote o UPP que no son de la empresa): explícalo y no reintentes con otros datos inventados. 'duplicate_skipped' = ya estaba registrado hace minutos (reintento): díselo, no es un parto nuevo. 'possible_duplicate' = la madre YA tiene un parto dentro de la ventana (por omisión 240 días) o un parto histórico cercano: muestra 'existing' (fecha, origen BIRTH/HISTORICAL) y NO registres nada; solo si el usuario confirma que es otro parto (por ejemplo un gemelo) repite la llamada con force = true. Si regresa 'recorded', confirma con los datos que trae (calf_id, category, dam_status_updated_to_vacia) y, si trae 'service_link', di si se ligó un servicio (status linked) o no (no_candidate / ambiguous: se deja sin ligar). Nunca digas que se registró si el status no es 'recorded'. ANTES de llamarla resume lo que se va a registrar y pide al usuario que confirme con Sí/No; llámala solo tras el Sí (regla del prompt, Fase 5).
- **Operation:** Execute Query
- **Query:**
```sql
SELECT public.sp_repro_register_birth($1::text, $2::text, $3::text, $4::text, $5::text, $6::text, $7::text, $8::text, $9::text, $10::text, $11::text, $12::text, $13::text) AS result;
```
- **Options → Query Parameters (Expression):**
```js
={{ (() => { const s = (v) => (v === undefined || v === null) ? '' : String(v); return [
  String($fromAI('tenant_id', "Numeric tenant/company id (id_company) of the current user, copied EXACTLY from the session context in the system prompt. Never guess, infer or default it.", 'number')),
  String($fromAI('user_email', "Copia el email del usuario EXACTAMENTE carácter por carácter desde el contexto de sesión (system prompt) — nunca lo reescribas de memoria ni lo abrevies. Un solo carácter de diferencia hace que el sistema no encuentre ningún dato.", 'string')),
  s($fromAI('calf_sex', "Sexo de la cría: MACHO o HEMBRA, tal como lo dijo el usuario.", 'string', null)),
  s($fromAI('dam_identifier', "Arete SINIIGA, RFID o número a fuego de la MADRE, exactamente como lo dio el usuario. Omite si das dam_id.", 'string', null)),
  s($fromAI('dam_id', "UUID de la madre, solo si ya lo tienes de una respuesta anterior (por ejemplo al resolver una ambigüedad). Omite si das dam_identifier.", 'string', null)),
  s($fromAI('birth_date', "Fecha del parto AAAA-MM-DD. Omite para usar hoy. No puede ser futura ni de hace más de un año (para partos antiguos usa register_historical_birth).", 'string', null)),
  s($fromAI('birth_weight_kg', "Peso al nacer en kg, sin comas (ej. 36.5). Omite si el usuario no lo dio.", 'string', null)),
  s($fromAI('lot_id', "UUID del lote, solo si ya lo resolviste. Omite si no.", 'string', null)),
  s($fromAI('production_unit_id', "UUID de la UPP, solo si ya lo resolviste. Omite si no.", 'string', null)),
  s($fromAI('paddock_id', "UUID del potrero, solo si ya lo resolviste. Omite si no.", 'string', null)),
  s($fromAI('species', "BOVINO (por omisión), BORREGO, BUFALO o EQUIDO. Omite para bovino.", 'string', null)),
  s($fromAI('notes', "Notas del usuario. Omite si no hay.", 'string', null)),
  s($fromAI('force', "'true' SOLO si el usuario ya confirmó, después de un possible_duplicate o duplicate_skipped, que es otro parto (gemelo). Omite en cualquier otro caso.", 'string', null))
]; })() }}
```

## `births_batch_preview`

- **Description (manual):** VISTA PREVIA de un bloque de partos (hasta 50 renglones): no guarda nada. 'items' es un arreglo JSON (como texto) con UN objeto por parto: {"dam_identifier": "..." o "dam_id": "...", "calf_sex": "MACHO|HEMBRA", "birth_date": "AAAA-MM-DD" (opcional), "birth_weight_kg": ".." (opcional), "lot_id" / "production_unit_id" (opcionales)}. Copia lo que dijo el usuario, sin completar ni corregir. Regresa 'lines' con el status de cada renglón (ok, ambiguous con candidates, not_found, possible_duplicate, invalid, duplicate_skipped) y 'can_register' (true solo si NINGÚN renglón tiene problema). Enséñale al usuario los renglones con problema y resuélvelos con él (elige madre ambigua por su arete, quita o corrige el renglón) ANTES de registrar. Solo lectura.
- **Operation:** Execute Query
- **Query:**
```sql
SELECT public.sp_repro_births_batch_preview($1::text, $2::text, $3::text, $4::text) AS result;
```
- **Options → Query Parameters (Expression):**
```js
={{ (() => { const s = (v) => (v === undefined || v === null) ? '' : String(v); return [
  String($fromAI('tenant_id', "Numeric tenant/company id (id_company) of the current user, copied EXACTLY from the session context in the system prompt. Never guess, infer or default it.", 'number')),
  String($fromAI('user_email', "Copia el email del usuario EXACTAMENTE carácter por carácter desde el contexto de sesión (system prompt) — nunca lo reescribas de memoria ni lo abrevies. Un solo carácter de diferencia hace que el sistema no encuentre ningún dato.", 'string')),
  s($fromAI('items', "Arreglo JSON (como texto) de partos, en el MISMO ORDEN en que el usuario los dio. Máximo 50. Nunca inventes ni omitas un renglón.", 'string', null)),
  s($fromAI('default_date', "Fecha AAAA-MM-DD que aplica a los renglones sin birth_date propia. Omite para usar hoy.", 'string', null))
]; })() }}
```

## `births_batch_register`

- **Description (manual):** REGISTRA un bloque de partos (hasta 50 renglones). Es TODO O NADA y vuelve a validar todo por su cuenta (no confía en ninguna vista previa): si CUALQUIER renglón es ambiguous, not_found, possible_duplicate o inválido regresa status 'rejected' con el detalle por renglón y NO se guarda ninguno. En ese caso dile al usuario cuáles fallaron y que no se guardó nada del bloque; corrige o quita esos renglones y repite el bloque COMPLETO, o registra aparte (con register_birth_checked y force) un gemelo o un parto repetido; nunca digas 'se guardaron algunos'. Si regresa 'recorded', resume cuántos se escribieron (written) y cuántos ya existían (duplicate_skipped) revisando 'results' renglón por renglón. Misma forma de 'items' que births_batch_preview. Úsala solo después de la vista previa y de la confirmación Sí del usuario. ANTES de llamarla resume lo que se va a registrar y pide al usuario que confirme con Sí/No; llámala solo tras el Sí (regla del prompt, Fase 5).
- **Operation:** Execute Query
- **Query:**
```sql
SELECT public.sp_repro_births_batch_register($1::text, $2::text, $3::text, $4::text) AS result;
```
- **Options → Query Parameters (Expression):**
```js
={{ (() => { const s = (v) => (v === undefined || v === null) ? '' : String(v); return [
  String($fromAI('tenant_id', "Numeric tenant/company id (id_company) of the current user, copied EXACTLY from the session context in the system prompt. Never guess, infer or default it.", 'number')),
  String($fromAI('user_email', "Copia el email del usuario EXACTAMENTE carácter por carácter desde el contexto de sesión (system prompt) — nunca lo reescribas de memoria ni lo abrevies. Un solo carácter de diferencia hace que el sistema no encuentre ningún dato.", 'string')),
  s($fromAI('items', "El MISMO arreglo JSON (como texto) que se previsualizó, ya con las ambigüedades resueltas. Máximo 50.", 'string', null)),
  s($fromAI('default_date', "Fecha AAAA-MM-DD común para los renglones sin birth_date. Omite para usar hoy.", 'string', null))
]; })() }}
```

## `register_historical_birth`

- **Description (manual):** Registra un parto HISTÓRICO de una madre (de una libreta vieja, de hace más de un año, o con fecha aproximada). NO crea ninguna cría, NO cambia el estatus de la madre (puede estar ya vendida o muerta) y es idempotente: repetirlo regresa duplicate_skipped. Precisión de la fecha: DAY (AAAA-MM-DD), MONTH (AAAA-MM) o YEAR (AAAA); usa la que el usuario realmente sabe, no la inventes. calf_sex es opcional (MACHO/HEMBRA); litter_position solo para gemelos (1 a 4). 'ambiguous' = el arete/fuego coincide con varios animales: muestra los candidatos y pide cuál. Un parto histórico con precisión DAY o MONTH cuenta para el aviso possible_duplicate de partos nuevos; uno con precisión YEAR no. Para anular uno registrado por error usa void_historical_birth. ANTES de llamarla resume lo que se va a registrar y pide al usuario que confirme con Sí/No; llámala solo tras el Sí (regla del prompt, Fase 5).
- **Operation:** Execute Query
- **Query:**
```sql
SELECT public.sp_repro_register_historical_birth($1::text, $2::text, $3::text, $4::text, $5::text, $6::text, $7::text, $8::text, $9::text, $10::text) AS result;
```
- **Options → Query Parameters (Expression):**
```js
={{ (() => { const s = (v) => (v === undefined || v === null) ? '' : String(v); return [
  String($fromAI('tenant_id', "Numeric tenant/company id (id_company) of the current user, copied EXACTLY from the session context in the system prompt. Never guess, infer or default it.", 'number')),
  String($fromAI('user_email', "Copia el email del usuario EXACTAMENTE carácter por carácter desde el contexto de sesión (system prompt) — nunca lo reescribas de memoria ni lo abrevies. Un solo carácter de diferencia hace que el sistema no encuentre ningún dato.", 'string')),
  s($fromAI('dam_identifier', "Arete SINIIGA, RFID o número a fuego de la madre. Omite si das dam_id.", 'string', null)),
  s($fromAI('dam_id', "UUID de la madre (de una respuesta anterior). Omite si das dam_identifier.", 'string', null)),
  s($fromAI('birth_date', "Fecha del parto: AAAA-MM-DD, AAAA-MM o AAAA según la precisión. No puede ser futura; no hay límite hacia atrás.", 'string', null)),
  s($fromAI('date_precision', "DAY, MONTH o YEAR. Omite para DAY.", 'string', null)),
  s($fromAI('calf_sex', "MACHO o HEMBRA si el usuario lo sabe. Omite si no.", 'string', null)),
  s($fromAI('litter_position', "Posición en la camada (1 a 4) solo si hubo gemelos. Omite para 1.", 'string', null)),
  s($fromAI('source', "HISTORICAL_NOTEBOOK (por omisión), HISTORICAL_SPREADSHEET o HISTORICAL_OTHER.", 'string', null)),
  s($fromAI('notes', "Notas del usuario. Omite si no hay.", 'string', null))
]; })() }}
```

## `void_historical_birth`

- **Description (manual):** Anula UN parto histórico registrado por error. Requiere su 'historical_birth_id' (de register_historical_birth o de list_historical_births) y el MOTIVO que da el usuario; nunca inventes el motivo. Solo se anula una vez ('already_voided'). 'not_found' = ese id no existe en la empresa. No cambia nada más (no toca animales ni partos registrados). ANTES de llamarla resume lo que se va a registrar y pide al usuario que confirme con Sí/No; llámala solo tras el Sí (regla del prompt, Fase 5).
- **Operation:** Execute Query
- **Query:**
```sql
SELECT public.sp_repro_void_historical_birth($1::text, $2::text, $3::text, $4::text) AS result;
```
- **Options → Query Parameters (Expression):**
```js
={{ (() => { const s = (v) => (v === undefined || v === null) ? '' : String(v); return [
  String($fromAI('tenant_id', "Numeric tenant/company id (id_company) of the current user, copied EXACTLY from the session context in the system prompt. Never guess, infer or default it.", 'number')),
  String($fromAI('user_email', "Copia el email del usuario EXACTAMENTE carácter por carácter desde el contexto de sesión (system prompt) — nunca lo reescribas de memoria ni lo abrevies. Un solo carácter de diferencia hace que el sistema no encuentre ningún dato.", 'string')),
  s($fromAI('historical_birth_id', "UUID del parto histórico, tal como lo regresó register_historical_birth o list_historical_births.", 'string', null)),
  s($fromAI('reason', "Motivo de la anulación, en palabras del usuario (mínimo 3 caracteres).", 'string', null))
]; })() }}
```

## `list_historical_births`

- **Description (manual):** Lista los partos históricos de la empresa (o de UNA madre si das su identificador), del más reciente al más antiguo, con precisión de la fecha, sexo de la cría si se sabe, quién lo capturó y si está anulado (por omisión se ocultan los anulados). Sirve para encontrar el 'historical_birth_id' que se va a anular. Solo lectura. Si regresa 'ambiguous', muestra los candidatos y pide cuál. Paginada con 'offset'.
- **Operation:** Execute Query
- **Query:**
```sql
SELECT public.sp_repro_list_historical_births($1::text, $2::text, $3::text, $4::text, $5::text, $6::text) AS result;
```
- **Options → Query Parameters (Expression):**
```js
={{ (() => { const s = (v) => (v === undefined || v === null) ? '' : String(v); return [
  String($fromAI('tenant_id', "Numeric tenant/company id (id_company) of the current user, copied EXACTLY from the session context in the system prompt. Never guess, infer or default it.", 'number')),
  String($fromAI('user_email', "Copia el email del usuario EXACTAMENTE carácter por carácter desde el contexto de sesión (system prompt) — nunca lo reescribas de memoria ni lo abrevies. Un solo carácter de diferencia hace que el sistema no encuentre ningún dato.", 'string')),
  s($fromAI('dam_identifier', "Arete SINIIGA, RFID o número a fuego de la madre. Omite para listar todos.", 'string', null)),
  s($fromAI('include_voided', "'true' para incluir los anulados. Omite para ocultarlos.", 'string', null)),
  s($fromAI('limit', "Máximo de partos (por omisión 50, tope 100).", 'string', null)),
  s($fromAI('offset', "Cuántos saltar para la siguiente página (0 por omisión).", 'string', null))
]; })() }}
```

## `get_births_config`

- **Description (manual):** Regresa la ventana (en días) con la que se avisa de un posible parto duplicado de la misma madre (por omisión 240, configurable por empresa entre 30 y 730). Solo lectura. Solo un ADMIN la cambia desde el panel; tú no puedes cambiarla.
- **Operation:** Execute Query
- **Query:**
```sql
SELECT public.sp_repro_births_get_config($1::text, $2::text) AS result;
```
- **Options → Query Parameters (Expression):**
```js
={{ (() => { const s = (v) => (v === undefined || v === null) ? '' : String(v); return [
  String($fromAI('tenant_id', "Numeric tenant/company id (id_company) of the current user, copied EXACTLY from the session context in the system prompt. Never guess, infer or default it.", 'number')),
  String($fromAI('user_email', "Copia el email del usuario EXACTAMENTE carácter por carácter desde el contexto de sesión (system prompt) — nunca lo reescribas de memoria ni lo abrevies. Un solo carácter de diferencia hace que el sistema no encuentre ningún dato.", 'string'))
]; })() }}
```

## `get_dam_reproductive_history`

- **Description (manual):** Historial reproductivo completo de UNA hembra: sus partos registrados (con la cría y el servicio ligado), sus partos históricos, sus servicios (anulados marcados), sus palpaciones con la condición uterina (repro_condition, código en bruto, estado del mapeo) y la condición de las cargas viejas, sus entradas a empadre, su estatus actual, la fecha estimada de parto (solo si está PREÑADA) y banderas de calidad de datos. Solo lectura. Si el arete o fuego coincide con varios animales regresa 'ambiguous' con los candidatos: pide cuál, nunca elijas. 🛑 Lee las 'quality_flags': si stale_import_date_company.flag es true, las palpaciones con on_stale_import_date = true tienen la fecha de una carga masiva, no la de una palpación real; un expected_calving.bucket 'stale_data' es un dato viejo, NO un parto próximo ni atrasado; un servicio sin birth_event_id no está ligado a ningún parto (no se adivina). Los partos históricos no tienen cría registrada. Muestra solo lo que regrese la herramienta.
- **Operation:** Execute Query
- **Query:**
```sql
SELECT public.sp_repro_get_dam_history($1::text, $2::text, $3::text, $4::text) AS result;
```
- **Options → Query Parameters (Expression):**
```js
={{ (() => { const s = (v) => (v === undefined || v === null) ? '' : String(v); return [
  String($fromAI('tenant_id', "Numeric tenant/company id (id_company) of the current user, copied EXACTLY from the session context in the system prompt. Never guess, infer or default it.", 'number')),
  String($fromAI('user_email', "Copia el email del usuario EXACTAMENTE carácter por carácter desde el contexto de sesión (system prompt) — nunca lo reescribas de memoria ni lo abrevies. Un solo carácter de diferencia hace que el sistema no encuentre ningún dato.", 'string')),
  s($fromAI('dam_identifier', "Arete SINIIGA, RFID o número a fuego de la hembra. Omite si das dam_id.", 'string', null)),
  s($fromAI('dam_id', "UUID de la hembra (de una respuesta anterior). Omite si das dam_identifier.", 'string', null))
]; })() }}
```
