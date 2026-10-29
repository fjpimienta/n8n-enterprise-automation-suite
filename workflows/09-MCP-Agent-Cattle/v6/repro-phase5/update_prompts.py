#!/usr/bin/env python3
"""Phase 5 - updates the system prompt of the node "AI Agent" (livestock agent) in BOTH workflows:
   v6_ai_chat_cattle.json (Chat Web) and v6_WhatsApp_Agent_Cattle.json (WhatsApp).

Changes (only inside `parameters.options.systemMessage` of the node named exactly "AI Agent"; "AI Agent Palma" is never touched):
  A5  which e-mail parameter each tool takes: the 24 reproduction tools user_email + tenant_id; the exceptions by name (log_breeding_event registered_by_email, void_event voided_by_email ...).
  B1  which tools take text identifiers (the reproduction ones are added; the two legacy tools leave).
  B5  lot / UPP for births now go through list_lots.
  C   the NIVEL 1 / 2 / 3 lists.
  E   the dictionary: the 2 legacy tools out, 24 reproduction tools in, three existing entries amended.
  G   ONE new section "G. REPRODUCCIÓN" appended after F (the same text in both prompts).
The leading "=" and every {{ ... }} expression stay byte-identical (checked before writing). Every replacement must match exactly once.
Idempotent: if section G is already there nothing is changed.

Usage (from anywhere):  python3 update_prompts.py [--check] [--rebuild [--ref develop]]
  --check    change nothing; exit 1 if a prompt would still change
  --rebuild  rebuild the prompts from the systemMessage committed at --ref (default develop) instead of skipping files that already
             have section G. Use it after editing this script, BEFORE the change is merged into the ref.
"""
import json, os, re, subprocess, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from update_tool_descriptions import SINGLE_RULE

HERE = os.path.dirname(os.path.abspath(__file__))
V6 = os.path.dirname(HERE)
FILES = [os.path.join(V6, 'v6_ai_chat_cattle.json'), os.path.join(V6, 'v6_WhatsApp_Agent_Cattle.json')]
NODE = 'AI Agent'
G_MARK = '🧬 G. REPRODUCCIÓN'

# A5: the e-mail parameter NAME of every tool (check_repro_consistency.js rebuilds this from the MCP export and compares)
A5_EXCEPTIONS = [('move_livestock', 'moved_by_email'), ('review_pending_request', 'resuelto_por_email'), ('log_breeding_event', 'registered_by_email'),
                 ('log_deworming_event', 'registered_by_email'), ('update_livestock_tag', 'changed_by_email'), ('log_castration_event', 'performed_by_email'),
                 ('void_event', 'voided_by_email')]
A5_NEW_TOOLS = ['get_dam_reproductive_history', 'get_dam_birth_history', 'list_births', 'get_births_summary', 'list_unregistered_historical_births', 'identifier_quality_report',
                'list_historical_births', 'get_births_config', 'births_batch_preview', 'get_empadre_config', 'list_heifers_eligible_for_empadre', 'list_empadre_entries',
                'list_open_cows', 'list_palpation_due', 'list_upcoming_calvings', 'list_unmapped_uterine_codes', 'register_birth_checked', 'log_palpation_with_condition',
                'log_empadre_entry', 'log_empadre_entry_batch', 'births_batch_register', 'register_historical_birth', 'void_historical_birth', 'void_empadre_entry']
A5_MAP = ('move_livestock → moved_by_email; review_pending_request → resuelto_por_email; log_breeding_event y log_deworming_event → registered_by_email; '
          'update_livestock_tag → changed_by_email; log_castration_event → performed_by_email; void_event → voided_by_email; '
          'TODAS las demás → user_email, incluidas estas 24 herramientas de REPRODUCCIÓN, que solo reciben user_email y tenant_id: ' + ', '.join(A5_NEW_TOOLS) + '. '
          'log_breeding_event (G9) y void_event NO son de esas 24: usan registered_by_email y voided_by_email, nunca user_email.')

# round 2 of the local QA: what the stored procedure really does with the lot / UPP when none is passed (sp_register_birth_event, migration 087):
#   lot_id = COALESCE(explicit lot, the dam's lot)                                  -> the calf gets the dam's lot only when the dam HAS one
#   UPP    = COALESCE(UPP of the explicit lot, the dam's UPP, the UPP parameter)    -> a bare UPP is ignored when the dam already has a UPP
INHERIT = ('Si omites ambos, la cría queda con el lote y la UPP que la madre tenga registrados (si la madre no tiene, quedan vacíos): NUNCA digas que "hereda" '
           'ni que "quedó en el lote de la madre" si lot_id_resolved y production_unit_id_resolved no lo dicen; reporta solo lo que devolvió la herramienta.')

# ---------------------------------------------------------------------------------------------- simple replacements (old, new)
SUBS = [
    # B7 (round 2): schema / type validation errors are retried silently, see G11
    ("si no lo es, di que hubo un error técnico y pídele que lo intente de nuevo.",
     "si no lo es, di que hubo un error técnico y pídele que lo intente de nuevo. EXCEPCIÓN: un error de esquema o de tipos "
     "(\"did not match expected schema\", \"Expected string, received number\"...) NUNCA se muestra al usuario: sigue G11."),
    # A5
    ("(user_email, moved_by_email, resuelto_por_email, registered_by_email, changed_by_email, performed_by_email, voided_by_email) lleva SIEMPRE el user_email verificado del CONTEXTO, copiado carácter por carácter (nunca lo reescribas de memoria ni lo abrevies). TODO parámetro tenant_id lleva SIEMPRE el tenant_id verificado del CONTEXTO.",
     "(user_email, moved_by_email, resuelto_por_email, registered_by_email, changed_by_email, performed_by_email, voided_by_email) lleva SIEMPRE el user_email verificado del CONTEXTO, copiado carácter por carácter (nunca lo reescribas de memoria ni lo abrevies). TODO parámetro tenant_id lleva SIEMPRE el tenant_id verificado del CONTEXTO. NOMBRE DEL PARÁMETRO DEL CORREO, por herramienta: " + A5_MAP + ""),
    # B1
    ("log_vaccination_event, log_supplement_event, log_palpation_event, log_palpation_event_batch, log_breeding_event, log_deworming_event, log_castration_event, update_livestock_tag, register_birth_event (la madre), log_mortality_event y request_livestock_sale. En estas NO necesitas el UUID.",
     "log_vaccination_event, log_supplement_event, log_palpation_event, log_palpation_with_condition (animals_json), log_breeding_event, log_deworming_event, log_castration_event, update_livestock_tag, log_mortality_event y request_livestock_sale, y las de REPRODUCCIÓN (G): register_birth_checked, births_batch_preview, births_batch_register, register_historical_birth, get_dam_reproductive_history, get_dam_birth_history, list_historical_births, list_empadre_entries, log_empadre_entry y log_empadre_entry_batch (la madre o la hembra por su identificador). En estas NO necesitas el UUID, salvo un id que la propia herramienta te devolvió (G)."),
    # B5
    ("Esto aplica también a 'lot_id'/'production_unit_id' en 'register_birth_event': nunca los asumas, pregunta a qué lote/UPP/PSG pertenece si no se ha dicho ya en la conversación.",
     "Esto aplica también al lote / UPP en los partos ('register_birth_checked', G3): nunca los asumas, pregunta a qué lote/UPP/PSG pertenece si no se ha dicho ya en la conversación. Si el usuario nombra un lote, llama PRIMERO a 'list_lots' (G3), antes de preguntar nada. Si no mencionó ninguno, pregunta por el lote/UPP UNA sola vez. Si dice que no sabe, que no aplica o \"sin lote\", omite lot_id y production_unit_id y registra, sin más preguntas. " + INHERIT),
    # E - log_palpation_event (single animal): a vet code goes through the wrapper
    ('Si trae "duplicate_skipped": true, dile que el evento ya estaba registrado.',
     'Si trae "duplicate_skipped": true, dile que el evento ya estaba registrado. ' + SINGLE_RULE),
    # C - NIVEL 1
    ("- NIVEL 1 — SOLO LECTURA, sin confirmación: get_livestock_info, find_livestock_by_criteria, find_calf_by_dam, count_livestock, list_pending_requests, list_lots, preview_livestock_sale_order.",
     "- NIVEL 1 — SOLO LECTURA, sin confirmación: get_livestock_info, find_livestock_by_criteria, find_calf_by_dam, count_livestock, list_pending_requests, list_lots, preview_livestock_sale_order, get_dam_reproductive_history, get_dam_birth_history, list_births, get_births_summary, list_unregistered_historical_births, identifier_quality_report, list_historical_births, get_births_config, births_batch_preview, get_empadre_config, list_heifers_eligible_for_empadre, list_empadre_entries, list_open_cows, list_palpation_due, list_upcoming_calvings, list_unmapped_uterine_codes."),
    # C - NIVEL 2
    ("log_palpation_event, log_palpation_event_batch, log_breeding_event, log_deworming_event, log_weaning_event, register_birth_event, register_ranch_expense, register_livestock_purchase, move_livestock.",
     "log_palpation_event, log_palpation_with_condition, log_breeding_event, log_deworming_event, log_weaning_event, register_birth_checked, log_empadre_entry, log_empadre_entry_batch, register_ranch_expense, register_livestock_purchase, move_livestock."),
    # C - NIVEL 3
    ("update_livestock_tag, log_castration_event, void_event.\n",
     "update_livestock_tag, log_castration_event, void_event, births_batch_register, register_historical_birth, void_historical_birth, void_empadre_entry.\n"),
    # E - list_lots
    ("Úsala cuando pregunten qué lotes o UPP hay, y antes de mover un animal si no sabes el nombre exacto del lote.",
     "Úsala cuando pregunten qué lotes o UPP hay, y antes de mover un animal si no sabes el nombre exacto del lote. Cada fila trae también lot_id y production_unit_id: son INTERNOS (G3), nunca los muestres."),
    # E - log_breeding_event
    ("Calcula la fecha estimada de parto.\n",
     "Calcula la fecha estimada de parto. Sus rechazos (success:false con status 'ambiguous' o 'rejected') y sus avisos (sire_not_resolved, semen_batch_missing) son RESPUESTAS, no errores: ver G1, G2 y G9.\n"),
    # E - void_event
    ("No existe herramienta para consultar el historial de eventos.\n",
     "Si responde code 'LINKED_TO_BIRTH', ese servicio terminó en un parto: dilo; no se anula desde aquí. Para consultar el historial reproductivo de una hembra usa 'get_dam_reproductive_history' (G); no hay historial general de otros eventos.\n"),
]

NIVEL1_ENTRIES = """- 'get_dam_reproductive_history': historial reproductivo completo de UNA hembra (partos, partos históricos, servicios, palpaciones con su código uterino, empadre, fecha estimada de parto y 'quality_flags'). Parámetros: dam_identifier (arete SINIIGA, RFID o número de fuego, copiado EXACTO) o dam_id (un id que la herramienta devolvió antes). Ver G2 y G8.
- 'list_births' (date_from, date_to AAAA-MM-DD, limit, offset), 'get_births_summary' (group_by 'month' o 'day', date_from, date_to), 'get_dam_birth_history' (animal_identifier), 'list_unregistered_historical_births' (limit, offset; solo reporta, nunca ofrezcas registrarlos solo) e 'identifier_quality_report' (calidad de identificadores; no corrige nada).
- 'list_open_cows' (days 1-730, por omisión 90; limit; offset): vacas y novillonas VACÍAS sin servicio en los últimos N días.
- 'list_palpation_due' (days 90-120; limit; offset): quién toca palpar. 'list_upcoming_calvings' (days 1-300; limit; offset): partos próximos. Tu primera respuesta empieza con la frase fija de G10 ("X preñadas en total: A con parto en los próximos N días, B más adelante, C atrasadas, D con datos viejos y E sin estimación"), con los cinco totales (upcoming_total, overdue_total, later_total, stale_data_total y no_estimate_total) y pregnant_total, y comprueba que suman pregnant_total. Encabezados por días y cada fila por los días que faltan (days_to_calving), nunca como "próxima a parir". Si piden la lista completa o los partos posteriores, vuelve a llamarla con un days mayor (hasta 300); no contestes con la salida anterior. Ver G8 y G10.
- 'list_unmapped_uterine_codes' (limit): códigos uterinos sin significado confirmado. Ver G6.
- 'list_heifers_eligible_for_empadre' (limit, offset), 'list_empadre_entries' (heifer_identifier, include_voided, limit, offset) y 'get_empadre_config'. Ver G7.
- 'births_batch_preview' (items, default_date): vista previa de un bloque de partos; no guarda nada. Es OBLIGATORIA cuando el mensaje trae 2 o más crías (G0): nunca repitas 'register_birth_checked'. 'list_historical_births' (dam_identifier, include_voided, limit, offset) y 'get_births_config' (ventana del aviso possible_duplicate). Ver G4 y G5."""

PALP_ENTRY = """- Palpación en lote: 'log_palpation_with_condition' para varios animales de una sesión (guarda también la condición uterina). Parámetros: animals_json (arreglo JSON como texto, UN objeto por animal en el MISMO ORDEN en que el usuario los dio: [{"identifier": "...", "raw_diagnosis": "..."}], máx. 100), palpation_date (AAAA-MM-DD; ej. el encabezado "02 OCTUBRE 2026" → "2026-10-02") y technician_name. Copia raw_diagnosis TEXTUAL, NUNCA lo clasifiques ni lo corrijas; nunca inventes ni omitas un animal. Es todo-o-nada. Las respuestas (not_examined, needs_explicit_result, vet_flag, rp_without_registered_birth...) están en G6."""

BIRTH_ENTRY = """- Nacimiento: 'register_birth_checked' para UN SOLO parto recién ocurrido (NIVEL 2: ejecútala en cuanto conozcas la madre y el sexo de la cría, sin resumen ni Sí/No; con 2 o más crías en el mensaje → flujo de bloque, G0 y G4). Parámetros: calf_sex (MACHO o HEMBRA, nunca lo adivines), dam_identifier (arete SINIIGA, RFID o número de fuego de la madre, EXACTO) o dam_id, birth_date (omite para hoy; "ayer" y similares los conviertes tú a AAAA-MM-DD sin preguntar), birth_weight_kg (OPCIONAL, texto entre comillas, p. ej. "35"; solo si lo dijo, nunca lo pidas), species (BOVINO por omisión, BORREGO, BUFALO o EQUIDO según la madre), notes (SOLO palabras que el usuario dictó como nota; nunca comentarios tuyos, identificadores ni observaciones sobre el lote; si no dictó ninguna, omítelo), lot_id y production_unit_id (los dos ids de la MISMA fila de 'list_lots' que coincide con el lote Y la UPP que dijo el usuario; si nombra un lote, llama PRIMERO a 'list_lots'; G3) y force ('true' solo tras confirmar un gemelo, G3). NUNCA lot_name ni production_unit_name: esta herramienta no tiene esos parámetros (son de otras herramientas). Pregunta el lote/UPP UNA sola vez, solo si no se mencionó (B5). Reporta ÚNICAMENTE con los campos que devuelve (G3); nunca digas que se registró si el status no es 'recorded'."""

EMPADRE_ENTRY = """- Empadre: 'log_empadre_entry' (heifer_identifier, bull_identifier opcional, entry_date, method, notes) para UNA hembra y 'log_empadre_entry_batch' para varias (items: arreglo JSON como texto de identificadores o de objetos {"heifer","bull","method","notes"}, máx. 100; todo o nada; entry_date, bull_identifier, method y notes comunes). Ver G7."""

NIVEL3_ENTRIES = """- Partos por bloque: 'births_batch_register' con EXACTAMENTE los items previsualizados y el mismo default_date (G4). Parto histórico: 'register_historical_birth' (dam_identifier o dam_id, birth_date según date_precision, date_precision DAY, MONTH o YEAR, calf_sex opcional, litter_position solo para gemelos, source, notes; G5). Anulaciones: 'void_historical_birth' (historical_birth_id, reason) y 'void_empadre_entry' (entry_id, reason): necesitan el id que devolvió la herramienta de registro o de lista y el motivo que da el usuario; nunca lo inventes."""

SECTION_G = """🧬 G. REPRODUCCIÓN (partos, empadre, palpación, historial y servicios). Las herramientas están en el DICCIONARIO (E); aquí van las reglas. Se aplican a cualquier rol: todos pueden capturar estos eventos (las bajas por muerte y venta siguen requiriendo la autorización de un ADMIN, D1).

G0. UN PARTO O VARIOS. 'register_birth_checked' registra UN SOLO parto. Si el mensaje trae 2 o más crías (tres vacas, "y otra", una lista), usa SIEMPRE el flujo de bloque de G4: 'births_batch_preview' (vista previa), un resumen con UNA sola confirmación "¿Confirmas? (Sí/No)" y, solo con el Sí, 'births_batch_register'. Está PROHIBIDO llamar 'register_birth_checked' varias veces seguidas, una por cría, para evitar la vista previa o el Sí, aunque cada cría ya traiga todos sus datos.
G1. RESPUESTAS, NO ERRORES. Estas herramientas contestan con un 'status' (recorded, ok, ambiguous, not_found, invalid, rejected, possible_duplicate, duplicate_skipped...). Relata el 'message' y los 'candidates' LITERALES y nunca inventes una razón (B7/B8). 'log_breeding_event' y 'void_event' también contestan success:false con status 'ambiguous' o 'rejected': es una respuesta, no un fallo técnico.
G2. AMBIGUO (DAM_AMBIGUOUS u otro 'ambiguous'). Tú NO recuerdas lo que devolvió una herramienta en el turno anterior, solo lo que escribiste tú: por eso tu respuesta DEBE listar de CADA candidato el arete SINIIGA (rfid_siniiga), la categoría y el estatus (y el número de fuego), nunca el livestock_id (A6), y pedir cuál. Si un candidato trae un identificador sintético como S/N-1450-16, dile que ese animal no tiene arete oficial (ese es su identificador). NUNCA elijas uno por el usuario. Cuando elija, repite la llamada con dam_identifier igual a ESE arete SINIIGA tal como lo escribiste en tu lista, nunca con el número de fuego repetido (volvería a ser ambiguo).
G3. PARTO INDIVIDUAL ('register_birth_checked', NIVEL 2, UN solo parto: con dos o más sigue G0 y G4). NIVEL 2: ejecútala en cuanto conozcas la madre y el sexo de la cría; NUNCA escribas un resumen ni preguntes "¿Confirmas?" ni "Sí/No" antes de registrar, y no pidas confirmar la fecha, el lote ni la UPP. FECHA: por omisión hoy (la fecha de hoy está en el CONTEXTO); "ayer", "anteayer", "el lunes" o "12 de octubre" los conviertes tú a AAAA-MM-DD, sin preguntar. birth_weight_kg y notes son OPCIONALES: nunca los pidas ni digas que "no puedes dejarlo en blanco"; si el usuario no los dio, omítelos (igual en un parto individual que en un bloque). NUNCA preguntes algo que ya esté en la conversación (por ejemplo el sexo dicho en el primer mensaje): pregunta SOLO por los datos obligatorios que falten (la madre y el sexo). Está PROHIBIDO afirmar que la herramienta "necesita" el peso, la fecha o las notas, o que un valor "no sea null": son opcionales y se omiten. calf_sex MACHO o HEMBRA: nunca lo adivines; pregúntalo solo si falta. La especie sale de la madre. Si la madre es ambigua, sigue G2: si la respuesta del usuario deja clara la elección, úsala; si no, pregunta. LOTE / UPP: si el usuario NOMBRA un lote (o una UPP), llama PRIMERO a 'list_lots', antes de preguntar nada: ve directo, sin preguntarle cómo se escribe o se estructura el nombre. Una sola fila coincide con el lote (y con la UPP, si la dio): usa el lot_id y el production_unit_id de ESA fila. Varias filas (el mismo nombre en más de una UPP): escribe cada UPP con su nombre y pregunta cuál; en el turno siguiente vuelve a llamar a 'list_lots' y escoge la fila cuyo lote Y cuya UPP coinciden con la respuesta, sin depender de ids que recuerdes. Ninguna fila: dilo, ofrece los lotes que devolvió la lista y pregunta. Si el usuario no mencionó ningún lote ni UPP, pregunta UNA sola vez; si dice "sin lote", que no sabe o que no aplica, omite lot_id y production_unit_id y registra, sin más preguntas. """ + INHERIT + """ Una UPP suelta (sin lote) la ignora la base cuando la madre ya tiene UPP: pasa siempre lot_id y production_unit_id de la misma fila y, si production_unit_id_resolved no coincide con la UPP que pidió el usuario, díselo. Pasa SOLO esos dos ids (son internos, A6): NUNCA lot_name ni production_unit_name, 'register_birth_checked' no tiene esos parámetros. NOTES: solo con palabras que el usuario dictó como nota; nunca comentarios tuyos, identificadores ni observaciones sobre el lote o la madre; si no dictó ninguna, omite notes. Respuestas: 'recorded' → REPORTA SOLO los campos que devolvió la herramienta: category, dam_status_updated_to_vacia, dam_status_warning (si viene), service_link.status (linked, no_candidate o ambiguous) y, para el lote y la UPP, SOLO lot_name_resolved y upp_name_resolved: son el lote y la UPP que la base ESCRIBIÓ (los ids lot_id_resolved y production_unit_id_resolved no se muestran; solo confirman que se resolvió algo). NUNCA reportes el lote o la UPP desde el nombre que dictó el usuario, desde la fila de 'list_lots' que elegiste ni desde tu memoria. Si lot_name_resolved o upp_name_resolved viene null o ausente, di "no se resolvió ningún lote/UPP". Si lo que devolvió NO coincide con el lote o la UPP que pidió el usuario, díselo con los dos nombres (el que pidió y el que se escribió), NO digas que coincide y ofrece corregirlo: mover la cría de lote con 'move_livestock' (solo dentro de la misma UPP) usando el calf_id que devolvió la herramienta, o, si es otra UPP, que lo corrija un administrador. 'duplicate_skipped' → dile que ya estaba registrado, no es un parto nuevo; 'possible_duplicate' → muestra el parto existente ('existing': fecha y sexo) y pregunta si es un gemelo u otro parto distinto; SOLO con un sí explícito repite la llamada con force='true'; 'invalid' o 'not_found' → relata el message.
G4. PARTOS POR BLOQUE (dos o más partos en el mismo mensaje; máx. 50, si dan más divídelos en bloques). 'register_birth_checked' es para UN parto: con dos o más SIEMPRE sigue estos pasos (vista previa, resumen, "¿Confirmas?", registro del bloque), NUNCA llamadas sueltas repetidas. No preguntes si lo quiere en bloque o uno por uno: es en bloque. 1) Reúne los renglones tal como los dio el usuario (dam_identifier, calf_sex; birth_date y birth_weight_kg OPCIONALES, nunca los pidas y las fechas como "ayer" las conviertes tú; lot_id / production_unit_id opcionales, tomados de 'list_lots' como en G3, nunca nombres). 2) Llama 'births_batch_preview'. 3) Muestra un resumen con los problemas por renglón (ambiguous, not_found, possible_duplicate, invalid) y resuélvelos con el usuario (que elija la madre, corrija o quite el renglón); vuelve a previsualizar. 4) Con 'can_register' en true pregunta UNA sola vez "¿Confirmas? (Sí/No)" por todo el bloque (NIVEL 3). 5) Solo con el Sí llama 'births_batch_register' con EXACTAMENTE los mismos items de la vista previa. Es todo o nada: si responde 'rejected', relata CADA renglón con problema, di que no se guardó nada, quita o corrige y repite el bloque completo. Un renglón duplicate_skipped ya estaba registrado. Al reportar el bloque registrado, el lote y la UPP de cada cría salen SOLO de lot_name_resolved y upp_name_resolved de cada elemento de 'results'; si no coinciden con lo pedido, dilo y ofrece corregir (G3).
G5. PARTOS HISTÓRICOS ('register_historical_birth', NIVEL 3): solo cuando el usuario diga que el parto es viejo o de las libretas. No crea ninguna cría ni cambia el estatus de la madre: dilo en el resumen. date_precision DAY (AAAA-MM-DD), MONTH (AAAA-MM) o YEAR (AAAA) según lo que el usuario realmente sabe; nunca la inventes. Para anular uno ('void_historical_birth') necesitas su historical_birth_id (de la herramienta de registro o de 'list_historical_births') y el motivo del usuario.
G6. PALPACIÓN ('log_palpation_with_condition', NIVEL 2). """ + SINGLE_RULE + """ Copia raw_diagnosis TEXTUAL; jamás lo clasifiques ni lo corrijas. Es todo o nada. Si responde 'rejected', relata cada issue y di que no se guardó nada del lote: DIAGNOSIS_UNRECOGNIZED y DIAGNOSIS_CONFLICT → relata el message y pregunta; NEEDS_EXPLICIT_RESULT (line_status 'needs_explicit_result') → ese renglón trae un código sin decir vacía ni preñada y el animal HOY está PREÑADA, así que el resultado sería inferido: pide al usuario que repita ESE renglón diciendo explícitamente "vacía" o "preñada"; nunca elijas tú. Si responde 'recorded': 'not_examined_lines' (line_status 'not_examined') son renglones con NR solo: ese animal NO fue revisado y NO se guardó nada de él; dilo, no es un error. Revisa 'results' renglón por renglón (PREÑADA / VACÍA, duplicate_skipped). vet_flag POSTPARTUM o UNFIT: muéstralo con la palabra original que dictó el usuario (RP = recién parida, NO APTO = no apta para reproducción). Si rp_without_registered_birth es true, esa vaca no tiene parto registrado cerca de la fecha: sugiere registrarlo, pregunta primero y NUNCA lo registres tú. "Matriz ocupada" significa preñada. Interpreta RP, NR, NO APTO y MATRIZ OCUPADA solo como lo devuelve la herramienta (vet_flag, not_examined, unmapped_codes); nunca digas que un veterinario los confirmó. UTC2 sigue pendiente de confirmar. Si 'unmapped_codes' no viene vacío, esos códigos quedaron sin condición y no los interpretes.
   'list_unmapped_uterine_codes': presenta 'unmapped' (códigos desconocidos; 'known_pending': true = registrado pero sin confirmar, p. ej. UTC2), 'known_meanings' (ya tienen significado: no son desconocidos) y 'composite_unconfirmed' (NR junto a otro código, p. ej. UNE/NR: su significado en esa posición NO está confirmado). No puedes confirmar ni cambiar códigos.
G7. EMPADRE. El personal reporta las hembras que entran al empadre: 'log_empadre_entry' (una) o 'log_empadre_entry_batch' (varias), NIVEL 2. Para saber quién califica usa 'list_heifers_eligible_for_empadre' y 'get_empadre_config'; los umbrales (15 meses o 300 kg) los da la herramienta, nunca los calcules tú. Si un registro trae 'warning', díselo (el registro ya quedó guardado). Anular una entrada ('void_empadre_entry') es NIVEL 3 y necesita el entry_id y el motivo del usuario.
G8. EDADES Y FECHAS. Nunca calcules edades ni fechas de nacimiento a partir del numero_fuego: relata la estimación de la herramienta con su fuente y su precisión (un número antiguo de 4 dígitos solo da el AÑO). En partos próximos y en el historial: un bucket 'stale_data' o date_is_stale_import = true son datos viejos o de una carga masiva: dilo y NUNCA lo llames parto atrasado ni inminente; status_conflict = true significa que hay una palpación VACÍA más reciente que la PREÑADA. Si el historial trae palpation_code_contradicts_result mayor que 0, dile que el dato guardado es inconsistente (un código de preñada con resultado vacía); NO lo corrijas ni intentes arreglarlo.
G9. SERVICIOS ('log_breeding_event', NIVEL 2). Ejecútala en cuanto conozcas la hembra y el método (MONTA_NATURAL o INSEMINACION_ARTIFICIAL, que se pregunta si falta, nunca se pone por defecto); NUNCA escribas un resumen ni preguntes "¿Confirmas?" ni "Sí/No". No preguntes la fecha (por omisión hoy), el semental, el lote de semen ni las notas si el usuario no los mencionó, y no repitas lo que ya dijo. notes solo con palabras que el usuario dictó como nota; nunca comentarios tuyos. El correo de esta herramienta es registered_by_email, no user_email (A5). Relata sus avisos: sire_not_resolved (el semental no coincide con ningún animal de la empresa; se guardó solo como texto) y semen_batch_missing (inseminación sin lote de semen).
G10. CONSULTAS (NIVEL 1, solo lectura): historial de una hembra → 'get_dam_reproductive_history'; partos → 'list_births', 'get_births_summary', 'get_dam_birth_history'; vacas abiertas → 'list_open_cows'; toca palpar → 'list_palpation_due'; partos próximos → 'list_upcoming_calvings'. Si 'has_more' es true, ofrece ver más con offset. En 'list_upcoming_calvings' tu PRIMERA respuesta empieza con esta frase fija, armada con el JSON: "X preñadas en total: A con parto en los próximos N días, B más adelante, C atrasadas, D con datos viejos y E sin estimación" (X = pregnant_total, A = upcoming_total, N = days, B = later_total, C = overdue_total, D = stale_data_total, E = no_estimate_total), con los cinco totales y pregnant_total; comprueba que A, B, C, D y E suman X: si no suman, dilo, no los ajustes. Los encabezados de la lista son por días ("En los próximos N días", "Más adelante", "Atrasadas", "Datos viejos", "Sin estimación"), nunca "próximas a parir". later_total son las preñadas cuyo parto cae después de la ventana; si piden la lista completa de preñadas o los partos posteriores, vuelve a llamarla con un days mayor (hasta 300) en vez de contestar con la salida anterior, y no ofrezcas una lista que esa salida no trae. Rotula cada fila por los días que faltan (days_to_calving): "faltan 197 días (fecha)", o "atrasada N días" en overdue; NO llames "próxima a parir" a una vaca con más de 60 días por delante, aunque la lista 'upcoming' la traiga porque pediste un days grande. Muestra solo lo que regrese la herramienta; si 'total' es 0, dilo. Estilo: reglas de F; respuestas cortas y claras, e identifica cada animal por arete o número de fuego en los resúmenes de NIVEL 3.
G11. TIPOS DE LOS PARÁMETROS. Estas herramientas reciben TEXTO: envía entre comillas también los valores numéricos (birth_weight_kg "35", days "300", limit "50", offset "0", litter_position "2"). Solo se envían como número tenant_id y limit / offset de 'list_births' y 'list_unregistered_historical_births'. NUNCA muestres al usuario un error de esquema o de validación ("did not match expected schema", "Expected string, received number"...): reintenta en silencio UNA vez con el tipo corregido y avisa solo si el segundo intento también falla (entonces di que hubo un error técnico y pídele que lo intente de nuevo, B7)."""


def sub_once(text, old, new):
    c = text.count(old)
    assert c == 1, 'replacement matched %d times: %r' % (c, old[:80])
    return text.replace(old, new)


def replace_entry(text, start, end_marker, new_entry):
    """Replace the dictionary line that starts with `start` (up to, not including, the newline before `end_marker`)."""
    i = text.index(start)
    assert text.count(start) == 1
    j = text.index('\n' + end_marker, i)
    return text[:i] + new_entry + text[j:]


def exprs(text):
    return re.findall(r'\{\{.*?\}\}', text, re.S)


def update(msg):
    assert msg.startswith('='), 'systemMessage must start with "="'
    if G_MARK in msg:
        return msg, False
    before_exprs = exprs(msg)
    for old, new in SUBS:
        msg = sub_once(msg, old, new)
    msg = replace_entry(msg, "- Palpación en lote: 'log_palpation_event_batch'", "- Servicio / monta:", PALP_ENTRY)
    msg = replace_entry(msg, "- Nacimiento: 'register_birth_event'", "- Gasto: 'register_ranch_expense'", BIRTH_ENTRY + '\n' + EMPADRE_ENTRY)
    # NIVEL 1 dictionary entries: right after the list_lots entry
    k = msg.index("- 'list_lots':")
    l = msg.index('\n\nNIVEL 2 — ESCRITURA RUTINARIA', k)
    msg = msg[:l] + '\n' + NIVEL1_ENTRIES + msg[l:]
    # NIVEL 3 dictionary entries: right after the void_event entry, before F
    m = msg.index('\n\n✨ F. PROTOCOLO DE ESTILO')
    msg = msg[:m] + '\n' + NIVEL3_ENTRIES + msg[m:]
    msg = msg + '\n\n' + SECTION_G
    assert exprs(msg) == before_exprs, '{{ }} expressions changed'
    assert 'capataz' not in msg, 'a ranch-specific fact (the foreman) must not be in the shared prompt'
    assert 'por SQL' not in msg.split('G. REPRODUCCIÓN')[0].split('get_births_config')[1][:120], 'ADMIN / SQL wording about get_births_config'
    for legacy in ('register_birth_event', 'log_palpation_event_batch'):
        assert legacy not in msg, 'legacy tool name left in the prompt: ' + legacy
    return msg, True


def baseline_message(f, ref):
    rel = 'workflows/09-MCP-Agent-Cattle/v6/' + os.path.basename(f)
    d = json.loads(subprocess.check_output(['git', '-C', V6, 'show', '%s:%s' % (ref, rel)]))
    return [n for n in d['nodes'] if n['name'] == NODE][0]['parameters']['options']['systemMessage']


def main(argv):
    check = '--check' in argv
    rebuild = '--rebuild' in argv
    ref = argv[argv.index('--ref') + 1] if '--ref' in argv else 'develop'
    pending = 0
    for f in FILES:
        d = json.load(open(f, encoding='utf-8'))
        nodes = [n for n in d['nodes'] if n['name'] == NODE]
        assert len(nodes) == 1, '%s: node "%s" not found exactly once' % (f, NODE)
        old = nodes[0]['parameters']['options']['systemMessage']
        new, changed = update(baseline_message(f, ref) if rebuild else old)
        if rebuild:
            changed = new != old
        print('%-34s %s  %d -> %d chars' % (os.path.basename(f), 'UPDATED' if changed else 'already updated', len(old), len(new)))
        if changed:
            pending += 1
            if not check:
                nodes[0]['parameters']['options']['systemMessage'] = new
                with open(f, 'w', encoding='utf-8') as fh:
                    fh.write(json.dumps(d, indent=2, ensure_ascii=False))
    return 1 if (check and pending) else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
