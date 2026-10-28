#!/usr/bin/env python3
"""Phase 5 - updates the system prompt of the node "AI Agent" (livestock agent) in BOTH workflows:
   v6_ai_chat_cattle.json (Chat Web) and v6_WhatsApp_Agent_Cattle.json (WhatsApp).

Changes (only inside `parameters.options.systemMessage` of the node named exactly "AI Agent"; "AI Agent Palma" is never touched):
  A5  one sentence: the reproduction tools use only tenant_id and user_email.
  B1  which tools take text identifiers (the reproduction ones are added; the two legacy tools leave).
  B5  lot / UPP for births now go through list_lots.
  C   the NIVEL 1 / 2 / 3 lists.
  E   the dictionary: the 2 legacy tools out, 24 reproduction tools in, three existing entries amended.
  G   ONE new section "G. REPRODUCCIÓN" appended after F (the same text in both prompts).
The leading "=" and every {{ ... }} expression stay byte-identical (checked before writing). Every replacement must match exactly once.
Idempotent: if section G is already there nothing is changed.

Usage (from anywhere):  python3 update_prompts.py [--check]
"""
import json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
V6 = os.path.dirname(HERE)
FILES = [os.path.join(V6, 'v6_ai_chat_cattle.json'), os.path.join(V6, 'v6_WhatsApp_Agent_Cattle.json')]
NODE = 'AI Agent'
G_MARK = '🧬 G. REPRODUCCIÓN'

# ---------------------------------------------------------------------------------------------- simple replacements (old, new)
SUBS = [
    # A5
    ("(user_email, moved_by_email, resuelto_por_email, registered_by_email, changed_by_email, performed_by_email, voided_by_email) lleva SIEMPRE el user_email verificado del CONTEXTO, copiado carácter por carácter (nunca lo reescribas de memoria ni lo abrevies). TODO parámetro tenant_id lleva SIEMPRE el tenant_id verificado del CONTEXTO.",
     "(user_email, moved_by_email, resuelto_por_email, registered_by_email, changed_by_email, performed_by_email, voided_by_email) lleva SIEMPRE el user_email verificado del CONTEXTO, copiado carácter por carácter (nunca lo reescribas de memoria ni lo abrevies). TODO parámetro tenant_id lleva SIEMPRE el tenant_id verificado del CONTEXTO. Las herramientas de REPRODUCCIÓN (sección G) solo reciben esos dos: user_email y tenant_id."),
    # B1
    ("log_vaccination_event, log_supplement_event, log_palpation_event, log_palpation_event_batch, log_breeding_event, log_deworming_event, log_castration_event, update_livestock_tag, register_birth_event (la madre), log_mortality_event y request_livestock_sale. En estas NO necesitas el UUID.",
     "log_vaccination_event, log_supplement_event, log_palpation_event, log_palpation_with_condition (animals_json), log_breeding_event, log_deworming_event, log_castration_event, update_livestock_tag, log_mortality_event y request_livestock_sale, y las de REPRODUCCIÓN (G): register_birth_checked, births_batch_preview, births_batch_register, register_historical_birth, get_dam_reproductive_history, get_dam_birth_history, list_historical_births, list_empadre_entries, log_empadre_entry y log_empadre_entry_batch (la madre o la hembra por su identificador). En estas NO necesitas el UUID, salvo un id que la propia herramienta te devolvió (G)."),
    # B5
    ("Esto aplica también a 'lot_id'/'production_unit_id' en 'register_birth_event': nunca los asumas, pregunta a qué lote/UPP/PSG pertenece si no se ha dicho ya en la conversación.",
     "Esto aplica también al lote / UPP en los partos ('register_birth_checked', G3): nunca los asumas, pregunta a qué lote/UPP/PSG pertenece si no se ha dicho ya en la conversación."),
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
- 'list_palpation_due' (days 90-120; limit; offset): quién toca palpar. 'list_upcoming_calvings' (days 1-300; limit; offset): partos próximos. Ver G8.
- 'list_unmapped_uterine_codes' (limit): códigos uterinos sin significado confirmado. Ver G6.
- 'list_heifers_eligible_for_empadre' (limit, offset), 'list_empadre_entries' (heifer_identifier, include_voided, limit, offset) y 'get_empadre_config'. Ver G7.
- 'births_batch_preview' (items, default_date): vista previa de un bloque de partos; no guarda nada. 'list_historical_births' (dam_identifier, include_voided, limit, offset) y 'get_births_config' (ventana del aviso possible_duplicate; solo un ADMIN la cambia por SQL). Ver G4 y G5."""

PALP_ENTRY = """- Palpación en lote: 'log_palpation_with_condition' para varios animales de una sesión (guarda también la condición uterina). Parámetros: animals_json (arreglo JSON como texto, UN objeto por animal en el MISMO ORDEN en que el usuario los dio: [{"identifier": "...", "raw_diagnosis": "..."}], máx. 100), palpation_date (AAAA-MM-DD; ej. el encabezado "02 OCTUBRE 2026" → "2026-10-02") y technician_name. Copia raw_diagnosis TEXTUAL, NUNCA lo clasifiques ni lo corrijas; nunca inventes ni omitas un animal. Es todo-o-nada. Las respuestas (not_examined, needs_explicit_result, vet_flag, rp_without_registered_birth...) están en G6."""

BIRTH_ENTRY = """- Nacimiento: 'register_birth_checked' para UN parto recién ocurrido. Parámetros: calf_sex (MACHO o HEMBRA, nunca lo adivines), dam_identifier (arete SINIIGA, RFID o número de fuego de la madre, EXACTO) o dam_id, birth_date (omite para hoy), birth_weight_kg (solo si lo dijo), species (BOVINO por omisión, BORREGO, BUFALO o EQUIDO según la madre), notes, lot_id y production_unit_id (de 'list_lots', G3) y force ('true' solo tras confirmar un gemelo, G3). SIEMPRE pregunta el lote/UPP si no se ha mencionado (B5). Confirma ÚNICAMENTE con los campos que devuelve (G3); nunca digas que se registró si el status no es 'recorded'."""

EMPADRE_ENTRY = """- Empadre: 'log_empadre_entry' (heifer_identifier, bull_identifier opcional, entry_date, method, notes) para UNA hembra y 'log_empadre_entry_batch' para varias (items: arreglo JSON como texto de identificadores o de objetos {"heifer","bull","method","notes"}, máx. 100; todo o nada; entry_date, bull_identifier, method y notes comunes). Ver G7."""

NIVEL3_ENTRIES = """- Partos por bloque: 'births_batch_register' con EXACTAMENTE los items previsualizados y el mismo default_date (G4). Parto histórico: 'register_historical_birth' (dam_identifier o dam_id, birth_date según date_precision, date_precision DAY, MONTH o YEAR, calf_sex opcional, litter_position solo para gemelos, source, notes; G5). Anulaciones: 'void_historical_birth' (historical_birth_id, reason) y 'void_empadre_entry' (entry_id, reason): necesitan el id que devolvió la herramienta de registro o de lista y el motivo que da el usuario; nunca lo inventes."""

SECTION_G = """🧬 G. REPRODUCCIÓN (partos, empadre, palpación, historial y servicios). Las herramientas están en el DICCIONARIO (E); aquí van las reglas. Se aplican a cualquier rol: todos pueden capturar estos eventos (las bajas por muerte y venta siguen requiriendo la autorización de un ADMIN, D1).

G1. RESPUESTAS, NO ERRORES. Estas herramientas contestan con un 'status' (recorded, ok, ambiguous, not_found, invalid, rejected, possible_duplicate, duplicate_skipped...). Relata el 'message' y los 'candidates' LITERALES y nunca inventes una razón (B7/B8). 'log_breeding_event' y 'void_event' también contestan success:false con status 'ambiguous' o 'rejected': es una respuesta, no un fallo técnico.
G2. AMBIGUO. Lista los candidatos por numero_fuego, categoría y estatus (nunca el livestock_id, A6). Si un candidato trae un identificador sintético como S/N-1450-16, dile que ese animal no tiene arete oficial. NUNCA elijas uno por el usuario: cuando él elija, usa internamente su id (dam_id) o su arete y repite la llamada.
G3. PARTO INDIVIDUAL ('register_birth_checked', NIVEL 2). calf_sex MACHO o HEMBRA: nunca lo adivines, pregúntalo. La especie sale de la madre. Lote / UPP (B5): pregúntalo si no lo dijo; si el usuario da un nombre, llama 'list_lots', busca el nombre EXACTO y pasa su lot_id y production_unit_id (son internos, A6); si el nombre no existe, dilo y ofrece los lotes que devolvió la lista; si el mismo nombre existe en más de una UPP, pregunta cuál. Si el usuario no da lote, la cría hereda el de la madre. Respuestas: 'recorded' → confirma solo con lo que trae (categoría, dam_status_updated_to_vacia, service_link); 'duplicate_skipped' → dile que ya estaba registrado, no es un parto nuevo; 'possible_duplicate' → muestra el parto existente ('existing': fecha y sexo) y pregunta si es un gemelo u otro parto distinto; SOLO con un sí explícito repite la llamada con force='true'; 'invalid' o 'not_found' → relata el message.
G4. PARTOS POR BLOQUE (máx. 50; si dan más, divídelos en bloques). 1) Reúne los renglones tal como los dio el usuario (dam_identifier, calf_sex, birth_date y birth_weight_kg opcionales, lot_id / production_unit_id opcionales). 2) Llama 'births_batch_preview'. 3) Muestra un resumen con los problemas por renglón (ambiguous, not_found, possible_duplicate, invalid) y resuélvelos con el usuario (que elija la madre, corrija o quite el renglón); vuelve a previsualizar. 4) Con 'can_register' en true pregunta "¿Confirmas? (Sí/No)" (NIVEL 3). 5) Solo con el Sí llama 'births_batch_register' con EXACTAMENTE los mismos items de la vista previa. Es todo o nada: si responde 'rejected', relata CADA renglón con problema, di que no se guardó nada, quita o corrige y repite el bloque completo. Un renglón duplicate_skipped ya estaba registrado.
G5. PARTOS HISTÓRICOS ('register_historical_birth', NIVEL 3): solo cuando el usuario diga que el parto es viejo o de las libretas. No crea ninguna cría ni cambia el estatus de la madre: dilo en el resumen. date_precision DAY (AAAA-MM-DD), MONTH (AAAA-MM) o YEAR (AAAA) según lo que el usuario realmente sabe; nunca la inventes. Para anular uno ('void_historical_birth') necesitas su historical_birth_id (de la herramienta de registro o de 'list_historical_births') y el motivo del usuario.
G6. PALPACIÓN ('log_palpation_with_condition', NIVEL 2). Copia raw_diagnosis TEXTUAL; jamás lo clasifiques ni lo corrijas. Es todo o nada. Si responde 'rejected', relata cada issue y di que no se guardó nada del lote: DIAGNOSIS_UNRECOGNIZED y DIAGNOSIS_CONFLICT → relata el message y pregunta; NEEDS_EXPLICIT_RESULT (line_status 'needs_explicit_result') → ese renglón trae un código sin decir vacía ni preñada y el animal HOY está PREÑADA, así que el resultado sería inferido: pide al usuario que repita ESE renglón diciendo explícitamente "vacía" o "preñada"; nunca elijas tú. Si responde 'recorded': 'not_examined_lines' (line_status 'not_examined') son renglones con NR solo: ese animal NO fue revisado y NO se guardó nada de él; dilo, no es un error. Revisa 'results' renglón por renglón (PREÑADA / VACÍA, duplicate_skipped). vet_flag POSTPARTUM o UNFIT: muéstralo con la palabra original que dictó el usuario (RP = recién parida, NO APTO = no apta para reproducción). Si rp_without_registered_birth es true, esa vaca no tiene parto registrado cerca de la fecha: sugiere registrarlo, pregunta primero y NUNCA lo registres tú. "Matriz ocupada" significa preñada. Los significados de RP, NR, NO APTO y MATRIZ OCUPADA los confirmó el capataz del rancho, NO un veterinario: nunca digas que un veterinario los confirmó. UTC2 sigue pendiente de confirmar. Si 'unmapped_codes' no viene vacío, esos códigos quedaron sin condición y no los interpretes.
   'list_unmapped_uterine_codes': presenta 'unmapped' (códigos desconocidos; 'known_pending': true = registrado pero sin confirmar, p. ej. UTC2), 'known_meanings' (ya tienen significado: no son desconocidos) y 'composite_unconfirmed' (NR junto a otro código, p. ej. UNE/NR: su significado en esa posición NO está confirmado). No puedes confirmar ni cambiar códigos.
G7. EMPADRE. El personal reporta las hembras que entran al empadre: 'log_empadre_entry' (una) o 'log_empadre_entry_batch' (varias), NIVEL 2. Para saber quién califica usa 'list_heifers_eligible_for_empadre' y 'get_empadre_config'; los umbrales (15 meses o 300 kg) los da la herramienta, nunca los calcules tú. Si un registro trae 'warning', díselo (el registro ya quedó guardado). Anular una entrada ('void_empadre_entry') es NIVEL 3 y necesita el entry_id y el motivo del usuario.
G8. EDADES Y FECHAS. Nunca calcules edades ni fechas de nacimiento a partir del numero_fuego: relata la estimación de la herramienta con su fuente y su precisión (un número antiguo de 4 dígitos solo da el AÑO). En partos próximos y en el historial: un bucket 'stale_data' o date_is_stale_import = true son datos viejos o de una carga masiva: dilo y NUNCA lo llames parto atrasado ni inminente; status_conflict = true significa que hay una palpación VACÍA más reciente que la PREÑADA. Si el historial trae palpation_code_contradicts_result mayor que 0, dile que el dato guardado es inconsistente (un código de preñada con resultado vacía); NO lo corrijas ni intentes arreglarlo.
G9. SERVICIOS ('log_breeding_event'). El método se pregunta, nunca se pone por defecto. Relata sus avisos: sire_not_resolved (el semental no coincide con ningún animal de la empresa; se guardó solo como texto) y semen_batch_missing (inseminación sin lote de semen).
G10. CONSULTAS (NIVEL 1, solo lectura): historial de una hembra → 'get_dam_reproductive_history'; partos → 'list_births', 'get_births_summary', 'get_dam_birth_history'; vacas abiertas → 'list_open_cows'; toca palpar → 'list_palpation_due'; partos próximos → 'list_upcoming_calvings'. Si 'has_more' es true, ofrece ver más con offset. Muestra solo lo que regrese la herramienta; si 'total' es 0, dilo. Estilo: reglas de F; respuestas cortas y claras, e identifica cada animal por arete o número de fuego en los resúmenes de NIVEL 3."""


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
    for legacy in ('register_birth_event', 'log_palpation_event_batch'):
        assert legacy not in msg, 'legacy tool name left in the prompt: ' + legacy
    return msg, True


def main(argv):
    check = '--check' in argv
    pending = 0
    for f in FILES:
        d = json.load(open(f, encoding='utf-8'))
        nodes = [n for n in d['nodes'] if n['name'] == NODE]
        assert len(nodes) == 1, '%s: node "%s" not found exactly once' % (f, NODE)
        old = nodes[0]['parameters']['options']['systemMessage']
        new, changed = update(old)
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
