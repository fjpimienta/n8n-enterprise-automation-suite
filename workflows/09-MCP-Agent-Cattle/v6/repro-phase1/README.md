# Reproducción fase 1 — tools de `v6/MCP Server Cattle` (migración 084)

Archivo importable: `repro_phase1_tools.json` (5 nodos `postgresTool` + conexión `ai_tool` hacia `MCP Server Cattle`).

**Cómo cargarlas (después de aplicar la 084):** abrir `v6/MCP Server Cattle` en el editor → pegar el contenido del JSON en el lienzo (Ctrl+V) → comprobar que cada tool quedó conectada a `MCP Server Cattle` (si no, arrastrar su salida *Tool* a la entrada *Tool* del MCP) → guardar → **Publish** → descargar el export y comprobar la huella.

⚠️ Las tools **no se ven para el agente** hasta que se agreguen a los dos *System Prompt* (Fase 5). Hasta entonces quedan inertes; el orden base de datos → n8n evita errores `function does not exist`.

Credencial: `Postgres account` (la misma de las demás tools). `tenant_id` y `user_email` siguen siendo `$fromAI` como en las otras tools de ganadería (deuda conocida, Regla 6); la base los valida de todos modos (`fn_repro_ctx`: membresía activa + empresa que no es de palma, falla con error).

## `list_births`

- **Description (manual):** Lista los partos registrados en un rango de fechas (por omisión, los últimos 30 días), del más reciente al más antiguo: madre (arete, número de fuego, RFID), cría si ya tiene registro, fecha, sexo, peso al nacer y UPP. Solo lectura, no requiere confirmación. Úsala cuando pregunten '¿ha parido alguna vaca?', '¿cuántos partos hubo este mes?' o '¿de qué vaca nació tal becerro?'. Paginada: si 'has_more' es true, ofrece ver más y vuelve a llamar con 'offset'. Nunca inventes partos: muestra solo lo que regrese la herramienta; si 'total' es 0, dilo así.
- **Operation:** Execute Query
- **Query:**
```sql
SELECT public.sp_repro_list_births($1::text, $2::text, $3::text, $4::text, $5::text, $6::text) AS result;
```
- **Options → Query Parameters (Expression):**
```js
={{ (() => { const s = (v) => (v === undefined || v === null) ? '' : String(v); return [
  String($fromAI('tenant_id', 'Numeric tenant/company id (id_company) of the current user, copied EXACTLY from the session context in the system prompt. Never guess, infer or default it.', 'number')),
  String($fromAI('user_email', 'Copia el email del usuario EXACTAMENTE carácter por carácter desde el contexto de sesión (system prompt) — nunca lo reescribas de memoria ni lo abrevies. Un solo carácter de diferencia hace que el sistema no encuentre ningún dato.', 'string')),
  s($fromAI('date_from', "Fecha inicial AAAA-MM-DD. Omite si el usuario no pidió un rango (se usan los últimos 30 días).", 'string', null)),
  s($fromAI('date_to', "Fecha final AAAA-MM-DD. Omite si el usuario no la dio (se usa hoy).", 'string', null)),
  s($fromAI('limit', "Máximo de partos a regresar (por omisión 50, tope 100). Omite si no es necesario.", 'number', null)),
  s($fromAI('offset', "Cuántos partos saltar para ver la siguiente página (0 por omisión).", 'number', null))
]; })() }}
```

## `get_dam_birth_history`

- **Description (manual):** Regresa todos los partos de UNA vaca (madre): fechas, sexo, cría y peso al nacer. Identifica a la madre con su arete SINIIGA, número de fuego o RFID, tal como el usuario lo escribió. Solo lectura. Si regresa status 'ambiguous', el identificador corresponde a varios animales (el número de fuego puede repetirse): muestra los 'candidates' (categoría, estatus, lote) y pide al usuario que indique cuál; NUNCA elijas uno. Si regresa 'not_found', dilo y no inventes datos.
- **Operation:** Execute Query
- **Query:**
```sql
SELECT public.sp_repro_dam_birth_history($1::text, $2::text, $3::text) AS result;
```
- **Options → Query Parameters (Expression):**
```js
={{ (() => { const s = (v) => (v === undefined || v === null) ? '' : String(v); return [
  String($fromAI('tenant_id', 'Numeric tenant/company id (id_company) of the current user, copied EXACTLY from the session context in the system prompt. Never guess, infer or default it.', 'number')),
  String($fromAI('user_email', 'Copia el email del usuario EXACTAMENTE carácter por carácter desde el contexto de sesión (system prompt) — nunca lo reescribas de memoria ni lo abrevies. Un solo carácter de diferencia hace que el sistema no encuentre ningún dato.', 'string')),
  s($fromAI('animal_identifier', "Arete SINIIGA, RFID electrónico o número de fuego de la madre, exactamente como lo escribió el usuario.", 'string', null))
]; })() }}
```

## `get_births_summary`

- **Description (manual):** Cuenta los partos por mes (por omisión, los últimos 12 meses) o por día (por omisión, los últimos 30 días), con machos y hembras. Solo lectura. Úsala para '¿cuántos partos llevamos este año?' o 'partos por mes'. Para rangos por día el máximo es un año.
- **Operation:** Execute Query
- **Query:**
```sql
SELECT public.sp_repro_births_summary($1::text, $2::text, $3::text, $4::text, $5::text) AS result;
```
- **Options → Query Parameters (Expression):**
```js
={{ (() => { const s = (v) => (v === undefined || v === null) ? '' : String(v); return [
  String($fromAI('tenant_id', 'Numeric tenant/company id (id_company) of the current user, copied EXACTLY from the session context in the system prompt. Never guess, infer or default it.', 'number')),
  String($fromAI('user_email', 'Copia el email del usuario EXACTAMENTE carácter por carácter desde el contexto de sesión (system prompt) — nunca lo reescribas de memoria ni lo abrevies. Un solo carácter de diferencia hace que el sistema no encuentre ningún dato.', 'string')),
  s($fromAI('group_by', "'month' (por omisión) o 'day'.", 'string', null)),
  s($fromAI('date_from', "Fecha inicial AAAA-MM-DD. Omite si el usuario no pidió un rango.", 'string', null)),
  s($fromAI('date_to', "Fecha final AAAA-MM-DD. Omite si el usuario no la dio.", 'string', null))
]; })() }}
```

## `list_unregistered_historical_births`

- **Description (manual):** REPORTE, no registra nada: lista las crías que tienen madre asignada pero NO tienen un registro de parto, con la madre, la cría y la fecha de nacimiento estimada (con su fuente y precisión: REGISTRADA o ESTIMADA_NUMERO_FUEGO; MONTH o YEAR_ONLY). Solo lectura. Úsala cuando pregunten por partos históricos sin registrar. Explica que la fecha estimada sale del número de fuego y que un número antiguo (4 dígitos) solo da el año, no el mes. Nunca ofrezcas registrarlos automáticamente.
- **Operation:** Execute Query
- **Query:**
```sql
SELECT public.sp_repro_list_unregistered_historical_births($1::text, $2::text, $3::text, $4::text) AS result;
```
- **Options → Query Parameters (Expression):**
```js
={{ (() => { const s = (v) => (v === undefined || v === null) ? '' : String(v); return [
  String($fromAI('tenant_id', 'Numeric tenant/company id (id_company) of the current user, copied EXACTLY from the session context in the system prompt. Never guess, infer or default it.', 'number')),
  String($fromAI('user_email', 'Copia el email del usuario EXACTAMENTE carácter por carácter desde el contexto de sesión (system prompt) — nunca lo reescribas de memoria ni lo abrevies. Un solo carácter de diferencia hace que el sistema no encuentre ningún dato.', 'string')),
  s($fromAI('limit', "Máximo de filas (por omisión 50, tope 100).", 'number', null)),
  s($fromAI('offset', "Cuántas filas saltar para la siguiente página (0 por omisión).", 'number', null))
]; })() }}
```

## `identifier_quality_report`

- **Description (manual):** Reporte de calidad de identificadores de los animales activos: números de fuego repetidos, aretes SINIIGA que no son de exactamente 10 dígitos, números de fuego de los que no se puede deducir la edad, animales sin RFID electrónico y RFID guardado como texto vacío. Solo lectura, no corrige nada. Úsala cuando pregunten por duplicados o por la calidad de los datos de identificación. Presenta los conteos y ejemplos tal cual los regresa la herramienta.
- **Operation:** Execute Query
- **Query:**
```sql
SELECT public.sp_repro_identifier_quality_report($1::text, $2::text) AS result;
```
- **Options → Query Parameters (Expression):**
```js
={{ (() => { const s = (v) => (v === undefined || v === null) ? '' : String(v); return [
  String($fromAI('tenant_id', 'Numeric tenant/company id (id_company) of the current user, copied EXACTLY from the session context in the system prompt. Never guess, infer or default it.', 'number')),
  String($fromAI('user_email', 'Copia el email del usuario EXACTAMENTE carácter por carácter desde el contexto de sesión (system prompt) — nunca lo reescribas de memoria ni lo abrevies. Un solo carácter de diferencia hace que el sistema no encuentre ningún dato.', 'string'))
]; })() }}
```
