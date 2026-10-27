# Reproducción fase 2 (empadre) — tools de `v6/MCP Server Cattle` (migración 085)

Archivo importable: `repro_phase2_tools.json` (7 nodos `postgresTool` + conexión `ai_tool` hacia `MCP Server Cattle`).

**Cómo cargarlas (después de aplicar la 085, que a su vez requiere la 084):** abrir `v6/MCP Server Cattle` en el editor → pegar el contenido del JSON en el lienzo (Ctrl+V) → comprobar que cada tool quedó conectada a `MCP Server Cattle` → guardar → **Publish** → descargar el export y comprobar la huella.

⚠️ Las tools **no se ven para el agente** hasta que se agreguen a los dos *System Prompt* (Fase 5). Hasta entonces quedan inertes. El orden base de datos → n8n evita errores `function does not exist`.

⚠️ **No hay tool para cambiar los mínimos de empadre** (`sp_repro_empadre_set_config`): solo un ADMIN la usa, por procedimiento, desde el panel o `psql`. El agente solo lee la configuración (`get_empadre_config`).

⚠️ **Las tres tools de escritura** (`log_empadre_entry`, `log_empadre_entry_batch`, `void_empadre_entry`) exigen en su descripción el Sí/No del usuario antes de llamarlas. Eso es una regla de prompt (como en el resto del agente de ganadería), no una garantía criptográfica: la regla debe repetirse en los dos *System Prompt* en la Fase 5.

Credencial: `Postgres account`. `tenant_id` y `user_email` siguen siendo `$fromAI` como en las demás tools de ganadería (deuda conocida, Regla 6); la base los valida de todos modos (`fn_repro_ctx`: membresía activa + empresa que no es de palma, falla con error).

Los parámetros opcionales están declarados `'string'` (no `'number'`) porque la query los castea con `$n::text` (Regla 15 del `CLAUDE.md` de agro-erp).

## `get_empadre_config`

- **Description (manual):** Regresa los mínimos de empadre de la empresa: edad mínima en meses (por omisión 15), peso mínimo en kg (por omisión 300), días tras los que un peso se considera antiguo y días que dura una entrada de empadre. Solo lectura. Úsala cuando pregunten '¿cuáles son los mínimos para meter a una novillona al empadre?'. Estos valores solo los cambia un ADMIN desde el panel; tú no puedes cambiarlos.
- **Operation:** Execute Query
- **Query:**
```sql
SELECT public.sp_repro_empadre_get_config($1::text, $2::text) AS result;
```
- **Options → Query Parameters (Expression):**
```js
={{ (() => { const s = (v) => (v === undefined || v === null) ? '' : String(v); return [
  String($fromAI('tenant_id', "Numeric tenant/company id (id_company) of the current user, copied EXACTLY from the session context in the system prompt. Never guess, infer or default it.", 'number')),
  String($fromAI('user_email', "Copia el email del usuario EXACTAMENTE carácter por carácter desde el contexto de sesión (system prompt) — nunca lo reescribas de memoria ni lo abrevies. Un solo carácter de diferencia hace que el sistema no encuentre ningún dato.", 'string'))
]; })() }}
```

## `list_heifers_eligible_for_empadre`

- **Description (manual):** Lista las hembras (NOVILLONA o BECERRA) que ya pueden entrar a empadre: activas, no preñadas y que no están ya en un empadre vigente, con edad >= el mínimo de meses O peso >= el mínimo de kg. Para cada una regresa el disparador (EDAD, PESO o AMBAS), la edad (con su fuente y precisión: una edad YEAR_ONLY solo conoce el año), el peso con su fecha de pesaje y si es antiguo (weight_stale), y 'category_possibly_outdated' (BECERRA puede estar desactualizada; la categoría NO se cambia sola). Aparte regresa 'sin_datos': hembras sin edad ni peso válidos, que no se pueden evaluar. Solo lectura. Paginada: si 'has_more' es true ofrece ver más con 'offset'. Muestra solo lo que regrese la herramienta.
- **Operation:** Execute Query
- **Query:**
```sql
SELECT public.sp_repro_list_heifers_eligible_for_empadre($1::text, $2::text, $3::text, $4::text) AS result;
```
- **Options → Query Parameters (Expression):**
```js
={{ (() => { const s = (v) => (v === undefined || v === null) ? '' : String(v); return [
  String($fromAI('tenant_id', "Numeric tenant/company id (id_company) of the current user, copied EXACTLY from the session context in the system prompt. Never guess, infer or default it.", 'number')),
  String($fromAI('user_email', "Copia el email del usuario EXACTAMENTE carácter por carácter desde el contexto de sesión (system prompt) — nunca lo reescribas de memoria ni lo abrevies. Un solo carácter de diferencia hace que el sistema no encuentre ningún dato.", 'string')),
  s($fromAI('limit', "Máximo de hembras por lista (por omisión 50, tope 100).", 'string', null)),
  s($fromAI('offset', "Cuántas saltar para la siguiente página (0 por omisión).", 'string', null))
]; })() }}
```

## `log_empadre_entry`

- **Description (manual):** Registra la entrada de UNA hembra a empadre (NOVILLONA, BECERRA o VACA). Identifica la hembra con su arete SINIIGA, RFID o número de fuego tal como el usuario lo dio; el toro (opcional) igual. NUNCA elijas entre varios animales: si regresa status 'ambiguous', muestra los 'candidates' y pide cuál. Si regresa 'recorded' con 'warning', dile al usuario la advertencia (no cumple 15 meses / 300 kg, no hay datos o el peso es antiguo): el registro YA quedó guardado, no se bloquea. 'duplicate_skipped' significa que ya estaba registrada (reintento): no la dupliques. Otros 'invalid' (preñada, vendida, toro que no es toro, ya en empadre, fecha inválida): explica el motivo con el 'message'. Guarda el 'entry_id' por si piden anularla. ANTES de llamarla resume lo que se va a registrar y pide al usuario que confirme con Sí/No; llámala solo tras el Sí (regla del prompt, Fase 5).
- **Operation:** Execute Query
- **Query:**
```sql
SELECT public.sp_repro_log_empadre_entry($1::text, $2::text, $3::text, $4::text, $5::text, $6::text, $7::text) AS result;
```
- **Options → Query Parameters (Expression):**
```js
={{ (() => { const s = (v) => (v === undefined || v === null) ? '' : String(v); return [
  String($fromAI('tenant_id', "Numeric tenant/company id (id_company) of the current user, copied EXACTLY from the session context in the system prompt. Never guess, infer or default it.", 'number')),
  String($fromAI('user_email', "Copia el email del usuario EXACTAMENTE carácter por carácter desde el contexto de sesión (system prompt) — nunca lo reescribas de memoria ni lo abrevies. Un solo carácter de diferencia hace que el sistema no encuentre ningún dato.", 'string')),
  s($fromAI('heifer_identifier', "Arete SINIIGA, RFID electrónico o número de fuego de la hembra, exactamente como lo escribió el usuario.", 'string', null)),
  s($fromAI('bull_identifier', "Arete SINIIGA, RFID o número de fuego del toro. Omite si el usuario no dio toro.", 'string', null)),
  s($fromAI('entry_date', "Fecha de entrada AAAA-MM-DD. Omite para usar hoy. No puede ser futura ni de hace más de un año.", 'string', null)),
  s($fromAI('method', "MONTA_NATURAL o INSEMINACION_ARTIFICIAL. Omite si el usuario no lo dijo.", 'string', null)),
  s($fromAI('notes', "Notas del usuario. Omite si no hay.", 'string', null))
]; })() }}
```

## `log_empadre_entry_batch`

- **Description (manual):** Registra la entrada de VARIAS hembras a empadre de una sola vez (máximo 100). Es TODO O NADA: si una sola tiene problema (no existe, es ambigua, está preñada, vendida, ya en empadre, toro inválido) NO se guarda ninguna y regresa status 'rejected' con 'issues' por renglón; explica cuáles fallaron y deja que el usuario corrija y repita el lote completo. 'items' es un arreglo JSON de identificadores, p. ej. ["0123456789","2097"], o de objetos {"heifer":"...","bull":"...","method":"...","notes":"..."}. El toro, método, fecha y notas comunes se aplican a todas las que no traigan los suyos. Un reintento exacto regresa 'duplicate_skipped' sin duplicar. En 'results' cada hembra con advertencia trae 'warning': díselas al usuario (ya quedaron guardadas). ANTES de llamarla resume lo que se va a registrar y pide al usuario que confirme con Sí/No; llámala solo tras el Sí (regla del prompt, Fase 5).
- **Operation:** Execute Query
- **Query:**
```sql
SELECT public.sp_repro_log_empadre_entry_batch($1::text, $2::text, $3::text, $4::text, $5::text, $6::text, $7::text) AS result;
```
- **Options → Query Parameters (Expression):**
```js
={{ (() => { const s = (v) => (v === undefined || v === null) ? '' : String(v); return [
  String($fromAI('tenant_id', "Numeric tenant/company id (id_company) of the current user, copied EXACTLY from the session context in the system prompt. Never guess, infer or default it.", 'number')),
  String($fromAI('user_email', "Copia el email del usuario EXACTAMENTE carácter por carácter desde el contexto de sesión (system prompt) — nunca lo reescribas de memoria ni lo abrevies. Un solo carácter de diferencia hace que el sistema no encuentre ningún dato.", 'string')),
  s($fromAI('items', "Arreglo JSON (como texto) de identificadores de hembras, o de objetos con heifer/bull/method/notes. Máximo 100.", 'string', null)),
  s($fromAI('entry_date', "Fecha de entrada AAAA-MM-DD para todo el lote. Omite para usar hoy.", 'string', null)),
  s($fromAI('bull_identifier', "Toro común del lote (arete SINIIGA, RFID o fuego). Omite si no aplica.", 'string', null)),
  s($fromAI('method', "MONTA_NATURAL o INSEMINACION_ARTIFICIAL para todo el lote. Omite si no aplica.", 'string', null)),
  s($fromAI('notes', "Notas comunes. Omite si no hay.", 'string', null))
]; })() }}
```

## `void_empadre_entry`

- **Description (manual):** Anula UNA entrada de empadre registrada por error. Requiere el 'entry_id' (de log_empadre_entry o de list_empadre_entries) y el MOTIVO que da el usuario; nunca inventes el motivo. Una entrada solo se anula una vez ('already_voided' si ya lo estaba). No cambia el estatus ni la categoría del animal. ANTES de llamarla resume lo que se va a registrar y pide al usuario que confirme con Sí/No; llámala solo tras el Sí (regla del prompt, Fase 5).
- **Operation:** Execute Query
- **Query:**
```sql
SELECT public.sp_void_empadre_entry($1::text, $2::text, $3::text, $4::text) AS result;
```
- **Options → Query Parameters (Expression):**
```js
={{ (() => { const s = (v) => (v === undefined || v === null) ? '' : String(v); return [
  String($fromAI('tenant_id', "Numeric tenant/company id (id_company) of the current user, copied EXACTLY from the session context in the system prompt. Never guess, infer or default it.", 'number')),
  String($fromAI('user_email', "Copia el email del usuario EXACTAMENTE carácter por carácter desde el contexto de sesión (system prompt) — nunca lo reescribas de memoria ni lo abrevies. Un solo carácter de diferencia hace que el sistema no encuentre ningún dato.", 'string')),
  s($fromAI('entry_id', "UUID de la entrada de empadre, tal como lo regresó log_empadre_entry o list_empadre_entries.", 'string', null)),
  s($fromAI('reason', "Motivo de la anulación, en palabras del usuario (mínimo 3 caracteres).", 'string', null))
]; })() }}
```

## `list_empadre_entries`

- **Description (manual):** Lista las entradas de empadre de la empresa (o de UNA hembra si das su identificador), de la más reciente a la más antigua, con toro, método, advertencia guardada, quién la registró y si está anulada. Por omisión oculta las anuladas. Sirve para encontrar el 'entry_id' que se va a anular. Solo lectura. Si regresa 'ambiguous', muestra los candidatos y pide cuál; nunca elijas. Paginada con 'offset'.
- **Operation:** Execute Query
- **Query:**
```sql
SELECT public.sp_repro_list_empadre_entries($1::text, $2::text, $3::text, $4::text, $5::text, $6::text) AS result;
```
- **Options → Query Parameters (Expression):**
```js
={{ (() => { const s = (v) => (v === undefined || v === null) ? '' : String(v); return [
  String($fromAI('tenant_id', "Numeric tenant/company id (id_company) of the current user, copied EXACTLY from the session context in the system prompt. Never guess, infer or default it.", 'number')),
  String($fromAI('user_email', "Copia el email del usuario EXACTAMENTE carácter por carácter desde el contexto de sesión (system prompt) — nunca lo reescribas de memoria ni lo abrevies. Un solo carácter de diferencia hace que el sistema no encuentre ningún dato.", 'string')),
  s($fromAI('heifer_identifier', "Arete SINIIGA, RFID o número de fuego de la hembra. Omite para listar todas.", 'string', null)),
  s($fromAI('include_voided', "'true' para incluir las anuladas. Omite para ocultarlas.", 'string', null)),
  s($fromAI('limit', "Máximo de entradas (por omisión 50, tope 100).", 'string', null)),
  s($fromAI('offset', "Cuántas saltar para la siguiente página (0 por omisión).", 'string', null))
]; })() }}
```

## `list_open_cows`

- **Description (manual):** Lista las vacas y novillonas VACÍAS que no han tenido servicio en los últimos N días (por omisión 90): primero las nunca servidas, luego las de servicio más antiguo. Para cada una regresa la fecha del último servicio, la fecha y resultado de su última palpación y si ya están en un empadre vigente (in_active_empadre). Los servicios anulados no cuentan. Solo lectura. Úsala para '¿qué vacas están abiertas?' o '¿cuáles llevan tiempo vacías sin servicio?'. Paginada: si 'has_more' es true ofrece ver más con 'offset'.
- **Operation:** Execute Query
- **Query:**
```sql
SELECT public.sp_repro_list_open_cows($1::text, $2::text, $3::text, $4::text, $5::text) AS result;
```
- **Options → Query Parameters (Expression):**
```js
={{ (() => { const s = (v) => (v === undefined || v === null) ? '' : String(v); return [
  String($fromAI('tenant_id', "Numeric tenant/company id (id_company) of the current user, copied EXACTLY from the session context in the system prompt. Never guess, infer or default it.", 'number')),
  String($fromAI('user_email', "Copia el email del usuario EXACTAMENTE carácter por carácter desde el contexto de sesión (system prompt) — nunca lo reescribas de memoria ni lo abrevies. Un solo carácter de diferencia hace que el sistema no encuentre ningún dato.", 'string')),
  s($fromAI('days', "Días sin servicio para considerar abierta (por omisión 90, de 1 a 730).", 'string', null)),
  s($fromAI('limit', "Máximo de vacas (por omisión 50, tope 100).", 'string', null)),
  s($fromAI('offset', "Cuántas saltar para la siguiente página (0 por omisión).", 'string', null))
]; })() }}
```
