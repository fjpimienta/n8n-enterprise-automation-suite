# Reproducción fase 3 (palpación con condición uterina, palpaciones pendientes, partos próximos) — tools de `v6/MCP Server Cattle` (migración 086)

Archivo importable: `repro_phase3_tools.json` (4 nodos `postgresTool` + conexión `ai_tool` hacia `MCP Server Cattle`).

**Cómo cargarlas (después de aplicar la 086, que requiere la 084 y la 085):** abrir `v6/MCP Server Cattle` en el editor → pegar el contenido del JSON en el lienzo (Ctrl+V) → comprobar que cada tool quedó conectada a `MCP Server Cattle` → guardar → **Publish** → descargar el export y comprobar la huella. Antes de importar, comparar producción contra `main` por huella (puede traer cambios manuales).

⚠️ Las tools **no se ven para el agente** hasta que se agreguen a los dos *System Prompt* (Fase 5). Hasta entonces quedan inertes. El orden base de datos → n8n evita errores `function does not exist`.

⚠️ **No se modifican** las tools `log_palpation_event` ni `log_palpation_event_batch` (ni `sp_log_palpation_event`): `log_palpation_with_condition` es una tool nueva que llama al mismo procedimiento. En la Fase 5 decide el prompt cuál de las dos usa el agente.

⚠️ **No hay tool para confirmar el significado de un código** (`sp_repro_condition_code_set`, solo ADMIN): lo confirma un ADMIN por procedimiento (panel o `psql`). El agente solo lista los pendientes (`list_unmapped_uterine_codes`).

⚠️ **`log_palpation_with_condition` escribe**: su descripción exige el Sí/No del usuario antes de llamarla. Es una regla de prompt (como en el resto del agente de ganadería), no una garantía criptográfica; la regla debe repetirse en los dos *System Prompt* en la Fase 5.

Credencial: `Postgres account`. `tenant_id` y `user_email` siguen siendo `$fromAI` como en las demás tools de ganadería (deuda conocida, Regla 6); la base los valida de todos modos (`fn_repro_ctx`: membresía activa + empresa que no es de palma, falla con error).

Los parámetros opcionales están declarados `'string'` (no `'number'`) porque la query los castea con `$n::text` (Regla 15 del `CLAUDE.md` de agro-erp).

## `log_palpation_with_condition`

- **Description (manual):** Registra en un solo lote los resultados de una sesión de palpación (varios animales) Y la condición uterina que el veterinario dictó. Hace lo mismo que log_palpation_event_batch (usa el mismo procedimiento de palpación) y además guarda la condición: CICLANDO, ESTATICA u OTRO cuando el código está confirmado para la empresa, o solo el código en bruto cuando todavía no lo está. Parámetros compartidos: technician_name y palpation_date (AAAA-MM-DD, hoy si se omite; no puede ser futura ni de hace más de un año). 'animals_json' es un arreglo JSON (como texto), UN objeto por animal en el MISMO ORDEN en que el usuario los dio: {"identifier": "...", "raw_diagnosis": "..."}.

🛑 CRÍTICO — NUNCA clasifiques, corrijas ni interpretes raw_diagnosis: cópialo EXACTAMENTE como lo dictó o escribió el usuario, con el código uterino incluido (ej. "VACÍA UNE", "VACIA UTCL2/OI", "VACÍA UNE/NR", "PREÑADA 02 MESES", "VACÍA ciclando"). La base decide PREÑADA/VACÍA, los días de gestación y la condición, y NO adivina: un diagnóstico sin palabra PREÑADA o VACÍA, sin 'ciclando'/'estática' y sin un código uterino (por ejemplo una falta de ortografía como 'PREÑDA' o texto libre) se rechaza, nunca se guarda como VACÍA; pide al usuario que lo aclare y no lo corrijas tú. Nunca inventes un código ni completes un dato que el usuario no dio.

🛑 Es TODO O NADA: si CUALQUIER renglón tiene problema (animal no encontrado, identificador ambiguo, animal vendido o muerto, animal repetido en el lote, renglón sin identifier o sin raw_diagnosis, o un diagnóstico que no se reconoce: DIAGNOSIS_UNRECOGNIZED, o que mezcla PREÑADA con VACÍA/condición: DIAGNOSIS_CONFLICT) regresa status 'rejected' con 'issues' por renglón (index, identifier, code, message; los ambiguos traen 'candidates') y NO se guarda ninguno. Explica cuáles fallaron, dile al usuario que no se guardó nada del lote y deja que corrija y repita el lote COMPLETO; en 'ambiguous' muestra los candidatos y pide cuál, nunca elijas. Si regresa 'recorded', revisa 'results' renglón por renglón y resume cuántas quedaron PREÑADA y cuántas VACÍA; señala 'duplicate_skipped' (ya estaba registrada, no es nueva) y cualquier 'gestation_note' (los meses/días de gestación estaban fuera de rango y no se guardaron).

🛑 Si 'unmapped_codes' no está vacío, díselo al usuario: esos códigos quedaron guardados tal cual pero SIN condición, porque los veterinarios aún no han confirmado su significado (no los interpretes tú). Cada resultado trae mapping_status: MAPPED (código confirmado), EXPLICIT (el usuario escribió 'ciclando' o 'estática'), UNMAPPED (código sin confirmar), NOT_APPLICABLE (sin código, o PREÑADA). ANTES de llamarla resume lo que se va a registrar y pide al usuario que confirme con Sí/No; llámala solo tras el Sí (regla del prompt, Fase 5).
- **Operation:** Execute Query
- **Query:**
```sql
SELECT public.sp_repro_log_palpation_batch($1::text, $2::text, $3::text, $4::text, $5::text) AS result;
```
- **Options → Query Parameters (Expression):**
```js
={{ (() => { const s = (v) => (v === undefined || v === null) ? '' : String(v); return [
  String($fromAI('tenant_id', "Numeric tenant/company id (id_company) of the current user, copied EXACTLY from the session context in the system prompt. Never guess, infer or default it.", 'number')),
  String($fromAI('user_email', "Copia el email del usuario EXACTAMENTE carácter por carácter desde el contexto de sesión (system prompt) — nunca lo reescribas de memoria ni lo abrevies. Un solo carácter de diferencia hace que el sistema no encuentre ningún dato.", 'string')),
  s($fromAI('animals_json', "Arreglo JSON, como texto, con UN objeto por animal, en el MISMO ORDEN en que aparecen en el mensaje del usuario. Cada objeto: {\"identifier\": \"<arete SINIIGA, RFID o número de fuego, exactamente como lo escribió el usuario>\", \"raw_diagnosis\": \"<el diagnóstico con su código uterino, verbatim>\"}. NUNCA interpretes, clasifiques ni corrijas el diagnóstico. NUNCA inventes ni omitas un renglón. Máximo 100.", 'string', null)),
  s($fromAI('palpation_date', "Fecha de TODAS las palpaciones del lote, AAAA-MM-DD. Omite para usar hoy.", 'string', null)),
  s($fromAI('technician_name', "Nombre del técnico o veterinario que hizo todas las palpaciones del lote, si el usuario lo dijo. Omite si no.", 'string', null))
]; })() }}
```

## `list_palpation_due`

- **Description (manual):** Lista las hembras que ya toca palpar: las PREÑADA y las que están en un empadre vigente cuya ÚLTIMA palpación es más antigua que N días (por omisión 90; configurable de 90 a 120). Las nunca palpadas salen primero (never_palpated) y luego las de palpación más antigua. Para cada una regresa el motivo (PREÑADA, EMPADRE o PREÑADA_Y_EMPADRE), la fecha y resultado de la última palpación y los días transcurridos. Solo lectura. Paginada: si 'has_more' es true ofrece ver más con 'offset'.

🛑 Revisa 'stale_import_date': si 'flag' es true, la mayoría de las palpaciones de la empresa comparten UNA fecha porque vienen de una carga masiva (no son palpaciones hechas ese día). Díselo al usuario y NO presentes esa fecha como la fecha real de la palpación ni calcules plazos con ella como si fuera real; los renglones afectados traen date_is_stale_import = true. Muestra solo lo que regrese la herramienta.
- **Operation:** Execute Query
- **Query:**
```sql
SELECT public.sp_repro_list_palpation_due($1::text, $2::text, $3::text, $4::text, $5::text) AS result;
```
- **Options → Query Parameters (Expression):**
```js
={{ (() => { const s = (v) => (v === undefined || v === null) ? '' : String(v); return [
  String($fromAI('tenant_id', "Numeric tenant/company id (id_company) of the current user, copied EXACTLY from the session context in the system prompt. Never guess, infer or default it.", 'number')),
  String($fromAI('user_email', "Copia el email del usuario EXACTAMENTE carácter por carácter desde el contexto de sesión (system prompt) — nunca lo reescribas de memoria ni lo abrevies. Un solo carácter de diferencia hace que el sistema no encuentre ningún dato.", 'string')),
  s($fromAI('days', "Días desde la última palpación para considerar que toca palpar (por omisión 90; de 90 a 120).", 'string', null)),
  s($fromAI('limit', "Máximo de hembras (por omisión 50, tope 100).", 'string', null)),
  s($fromAI('offset', "Cuántas saltar para la siguiente página (0 por omisión).", 'string', null))
]; })() }}
```

## `list_upcoming_calvings`

- **Description (manual):** Lista las hembras PREÑADA con fecha estimada de parto en los próximos N días (por omisión 60; de 1 a 300), de la más cercana a la más lejana. La fecha estimada es la fecha de la última palpación PREÑADA + (283 - días de gestación de esa palpación); si no hay días de gestación, el último servicio + 283 días. Solo lectura. Regresa varias listas: 'upcoming' (próximos partos), 'overdue' (estimados vencidos hasta 60 días), 'stale_data' (estimados vencidos por MÁS de 60 días), 'no_estimate' (PREÑADA sin base para estimar) y los totales de cada una.

🛑 'stale_data' son datos viejos o sin actualizar (por ejemplo palpaciones de una carga masiva que nunca se volvieron a revisar): NUNCA los anuncies como partos próximos ni atrasados; di solo cuántas hay y que su palpación necesita revisarse. Si 'stale_import_date.flag' es true, la fecha de esas palpaciones es la de una carga masiva, no una palpación real. Un renglón con status_conflict = true tiene una palpación VACÍA más reciente que la PREÑADA: su estatus necesita revisión. Muestra solo lo que regrese la herramienta. Paginada con 'offset'.
- **Operation:** Execute Query
- **Query:**
```sql
SELECT public.sp_repro_list_upcoming_calvings($1::text, $2::text, $3::text, $4::text, $5::text) AS result;
```
- **Options → Query Parameters (Expression):**
```js
={{ (() => { const s = (v) => (v === undefined || v === null) ? '' : String(v); return [
  String($fromAI('tenant_id', "Numeric tenant/company id (id_company) of the current user, copied EXACTLY from the session context in the system prompt. Never guess, infer or default it.", 'number')),
  String($fromAI('user_email', "Copia el email del usuario EXACTAMENTE carácter por carácter desde el contexto de sesión (system prompt) — nunca lo reescribas de memoria ni lo abrevies. Un solo carácter de diferencia hace que el sistema no encuentre ningún dato.", 'string')),
  s($fromAI('days', "Ventana en días hacia adelante (por omisión 60; de 1 a 300).", 'string', null)),
  s($fromAI('limit', "Máximo de hembras por lista (por omisión 50, tope 100).", 'string', null)),
  s($fromAI('offset', "Cuántas saltar para la siguiente página (0 por omisión).", 'string', null))
]; })() }}
```

## `list_unmapped_uterine_codes`

- **Description (manual):** Lista los códigos uterinos que aparecen en las palpaciones de la empresa y NO tienen todavía un significado confirmado (CICLANDO, ESTATICA u OTRO), con cuántas palpaciones los traen y valores de ejemplo, para que los veterinarios los completen. Se listan por código individual: 'UNE/NR' aporta 'NR' si 'UNE' ya está confirmado. También regresa 'confirmed', los códigos ya confirmados con quién los confirmó. Solo lectura. Tú NO puedes confirmar ni cambiar un significado: un ADMIN lo hace desde el panel. Nunca interpretes un código sin confirmar.
- **Operation:** Execute Query
- **Query:**
```sql
SELECT public.sp_repro_list_unmapped_uterine_codes($1::text, $2::text, $3::text) AS result;
```
- **Options → Query Parameters (Expression):**
```js
={{ (() => { const s = (v) => (v === undefined || v === null) ? '' : String(v); return [
  String($fromAI('tenant_id', "Numeric tenant/company id (id_company) of the current user, copied EXACTLY from the session context in the system prompt. Never guess, infer or default it.", 'number')),
  String($fromAI('user_email', "Copia el email del usuario EXACTAMENTE carácter por carácter desde el contexto de sesión (system prompt) — nunca lo reescribas de memoria ni lo abrevies. Un solo carácter de diferencia hace que el sistema no encuentre ningún dato.", 'string')),
  s($fromAI('limit', "Máximo de códigos (por omisión 100, tope 200).", 'string', null))
]; })() }}
```
