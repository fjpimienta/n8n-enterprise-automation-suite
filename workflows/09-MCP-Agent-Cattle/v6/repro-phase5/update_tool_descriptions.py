#!/usr/bin/env python3
"""Phase 5 - edits ONLY the `toolDescription` text of some nodes in the repro-phase1..4 tool files.

Why: the descriptions written in phases 1-4 predate the owner's decisions (confirmation levels) and migration 090:
  * NIVEL 2 tools (log_empadre_entry, log_empadre_entry_batch, log_palpation_with_condition, register_birth_checked) must NOT ask for
    a Si/No before running; NIVEL 3 tools (void_empadre_entry, births_batch_register, register_historical_birth, void_historical_birth)
    keep that sentence.
  * three descriptions say an ADMIN changes settings / codes "from the panel": there is no panel, it is SQL.
  * the palpation description must teach the 090 answers (not_examined, needs_explicit_result, vet_flag ...).
Every replacement must match EXACTLY ONCE (the script aborts otherwise) and nothing but `toolDescription` is touched (round 1 of the local QA
also edits the `$fromAI` hint texts of lot_id / production_unit_id / notes of register_birth_checked, see QR_EDITS).
Idempotent: a second run finds nothing to replace and changes nothing.

Usage (from the v6 folder):  python3 repro-phase5/update_tool_descriptions.py [--check]
  --check   change nothing; exit 1 if any description still needs an edit.
"""
import json, sys, os

HERE = os.path.dirname(os.path.abspath(__file__))
V6 = os.path.dirname(HERE)
FILES = {p: os.path.join(V6, 'repro-phase%d' % p, 'repro_phase%d_tools.json' % p) for p in (1, 2, 3, 4)}

CONFIRM = ' ANTES de llamarla resume lo que se va a registrar y pide al usuario que confirme con Sí/No; llámala solo tras el Sí (regla del prompt, Fase 5).'
NIVEL2 = ' Es una escritura rutinaria (NIVEL 2): ejecútala en cuanto tengas los datos obligatorios, SIN resumen previo ni pedir confirmación, y después reporta el resultado tal como lo devolvió.'

P090 = (' 🛑 Respuestas de la migración 090: (1) renglón con NR SOLO: aparece en not_examined_lines con line_status \'not_examined\' — el animal NO fue revisado, se validó pero NO se guardó NADA de él (ni palpación ni cambio de estatus); no es un error y los demás renglones sí se guardan; díselo al usuario. '
        '(2) issue NEEDS_EXPLICIT_RESULT (line_status \'needs_explicit_result\'): un renglón con solo un código, sin decir vacía ni preñada, sobre un animal que HOY está PREÑADA; el resultado sería inferido y podría borrar una gestación real, así que se rechaza ese renglón y con él TODO el lote (no se guardó nada): pide al usuario que repita ESE renglón diciendo explícitamente "vacía" o "preñada"; nunca elijas tú. '
        '(3) DIAGNOSIS_UNRECOGNIZED y DIAGNOSIS_CONFLICT: relata el message y pregunta; no corrijas. '
        '(4) vet_flag en un resultado: POSTPARTUM (código RP, recién parida) o UNFIT (NO APTO, no apta para reproducción); muéstralo con la palabra original que dictó el usuario. Si el resultado trae rp_without_registered_birth = true, esa vaca no tiene parto registrado cerca de la fecha: sugiere registrarlo, pregunta primero y NUNCA lo registres por tu cuenta. '
        '(5) "MATRIZ OCUPADA" significa preñada. Los significados de RP, NR, NO APTO y MATRIZ OCUPADA los confirmó el capataz del rancho, NO un veterinario: nunca digas que un veterinario los confirmó.')

SINGLE_RULE = ('Si el usuario dicta un código (UNE, UTCL1, RP, NR, NO APTO, MATRIZ OCUPADA...), usa log_palpation_with_condition con UN solo elemento '
               'en animals_json, aunque sea un solo animal. log_palpation_event es solo para un resultado explícito sin código.')

# round 1 of the local QA (2026-10-28): register_birth_checked
BIRTH_LOT_OLD = (' Para asignar lote o UPP usa los campos lot_id y production_unit_id de list_lots, buscando el nombre EXACTO que dio el usuario '
                 '(nunca los inventes ni se los muestres al usuario); si no dijo ninguno, la cría hereda de la madre.')
BIRTH_LOT_NEW = (' Para asignar lote o UPP pasa lot_id y production_unit_id tomados de la MISMA fila de list_lots, la que coincide con el nombre del lote Y con el de la UPP '
                 'que dio el usuario (nunca los inventes ni se los muestres al usuario). NUNCA lot_name ni production_unit_name: esta herramienta no tiene esos parámetros. '
                 'Si no dijo ninguno o dijo "sin lote", omite lot_id y production_unit_id y la cría hereda de la madre. '
                 'notes lleva SOLO palabras que el usuario dictó como nota; nunca comentarios tuyos, identificadores ni observaciones sobre el lote.')
BIRTH_NIVEL2_EXTRA = (' Ejecútala en cuanto conozcas la madre y el sexo de la cría; no preguntes la fecha (por omisión hoy), el peso ni las notas si el usuario no los mencionó, '
                      'ni vuelvas a preguntar lo que ya dijo. Es para UN parto: con dos o más partos en el mismo mensaje usa births_batch_preview.')

# descriptions to strip entirely (the sentence said an ADMIN changes the births window "desde el panel" / "por SQL": not wanted in the node)
REMOVE = [
    (4, 'get_births_config', [' Solo un ADMIN la cambia desde el panel; tú no puedes cambiarla.',
                              ' Solo un ADMIN la cambia por SQL (no hay pantalla); tú no puedes cambiarla.']),
]

# an edit whose result a LATER edit rewrote counts as applied when the later text is present (key: node name, old text)
DONE_ALSO = {('register_birth_checked', CONFIRM): (BIRTH_LOT_NEW,)}

# (file phase, node name, old, new)
EDITS = [
    (2, 'log_empadre_entry', CONFIRM, NIVEL2),
    (2, 'log_empadre_entry_batch', CONFIRM, NIVEL2),
    (4, 'register_birth_checked', CONFIRM,
     ' Para asignar lote o UPP usa los campos lot_id y production_unit_id de list_lots, buscando el nombre EXACTO que dio el usuario (nunca los inventes ni se los muestres al usuario); si no dijo ninguno, la cría hereda de la madre.' + NIVEL2),
    (3, 'log_palpation_with_condition', CONFIRM, P090 + NIVEL2),
    (3, 'log_palpation_with_condition',
     'porque los veterinarios aún no han confirmado su significado (no los interpretes tú).',
     'porque su significado aún no está confirmado (no los interpretes tú).'),
    (3, 'list_unmapped_uterine_codes',
     'Tú NO puedes confirmar ni cambiar un significado: un ADMIN lo hace desde el panel. Nunca interpretes un código sin confirmar.',
     'Tú NO puedes confirmar ni cambiar un significado: los códigos los carga un administrador por SQL (no hay pantalla para hacerlo). Nunca interpretes un código sin confirmar. '
     'También regresa \'known_meanings\' (códigos con significado: NR no revisada, RP recién parida, NO APTO no apta para reproducción, y la frase MATRIZ OCUPADA = preñada; YA NO son desconocidos), '
     '\'composite_unconfirmed\' (NR junto a otro código, p. ej. UNE/NR: su significado en esa posición NO está confirmado) y \'meanings_configured\' (quién confirmó cada significado: el capataz, NO un veterinario). UTC2 sigue pendiente (known_pending).'),
    (2, 'get_empadre_config',
     'Estos valores solo los cambia un ADMIN desde el panel; tú no puedes cambiarlos.',
     'Estos valores solo los cambia un ADMIN por SQL (no hay pantalla); tú no puedes cambiarlos.'),
    # insertion: the wrapper is also THE tool for one animal with a code (new text CONTAINS the old one, so the "already applied" test is `new in d`)
    (3, 'log_palpation_with_condition', ' 🛑 Respuestas de la migración 090: (1)', ' ' + SINGLE_RULE + ' 🛑 Respuestas de la migración 090: (1)'),
    # round 1 of the local QA: "confirma" reads as "ask the user to confirm" -> "reporta"; ids from list_lots; never names; notes; one birth
    (4, 'register_birth_checked', "Si regresa 'recorded', confirma con los datos que trae", "Si regresa 'recorded', reporta con los datos que trae"),
    (4, 'register_birth_checked', BIRTH_LOT_OLD, BIRTH_LOT_NEW),
    (4, 'register_birth_checked', NIVEL2, NIVEL2 + BIRTH_NIVEL2_EXTRA),
]

# (file phase, node name, old, new) inside options.queryReplacement: the hint texts of the $fromAI keys (no double quotes inside them)
QR_EDITS = [
    (4, 'register_birth_checked', '$fromAI(\'lot_id\', "UUID del lote, solo si ya lo resolviste. Omite si no."',
     '$fromAI(\'lot_id\', "UUID del lote: la columna lot_id de la fila de list_lots que coincide con el lote Y la UPP que dio el usuario. NUNCA un nombre de lote. Omite si no hay lote."'),
    (4, 'register_birth_checked', '$fromAI(\'production_unit_id\', "UUID de la UPP, solo si ya lo resolviste. Omite si no."',
     '$fromAI(\'production_unit_id\', "UUID de la UPP: la columna production_unit_id de la MISMA fila de list_lots. NUNCA un nombre de UPP. Omite si no hay UPP."'),
    (4, 'register_birth_checked', '$fromAI(\'notes\', "Notas del usuario. Omite si no hay."',
     '$fromAI(\'notes\', "SOLO palabras que el usuario dictó como nota. Nunca comentarios tuyos, identificadores ni observaciones sobre el lote. Omite si no dictó ninguna."'),
]


def main(argv):
    check = '--check' in argv
    data = {p: json.load(open(f, encoding='utf-8')) for p, f in FILES.items()}
    pending = 0
    for ph, node, old, new in EDITS:
        n = [x for x in data[ph]['nodes'] if x['name'] == node]
        assert len(n) == 1, 'node %s not found exactly once in phase %d' % (node, ph)
        d = n[0]['parameters']['toolDescription']
        if new in d or any(m in d for m in DONE_ALSO.get((node, old), ())):
            continue                                     # already applied (or superseded by a later edit of the same text)
        if old in d:
            assert d.count(old) == 1, 'replacement matches more than once in %s' % node
            pending += 1
            if not check:
                n[0]['parameters']['toolDescription'] = d.replace(old, new)
        else:
            raise SystemExit('ABORT: neither the old nor the new text is in %s (edited by hand?)' % node)
    for ph, node, old, new in QR_EDITS:
        n = [x for x in data[ph]['nodes'] if x['name'] == node]
        assert len(n) == 1, 'node %s not found exactly once in phase %d' % (node, ph)
        q = n[0]['parameters']['options']['queryReplacement']
        if new in q:
            continue
        assert q.count(old) == 1, 'queryReplacement hint of %s not found exactly once (edited by hand?)' % node
        pending += 1
        if not check:
            n[0]['parameters']['options']['queryReplacement'] = q.replace(old, new)
    for ph, node, candidates in REMOVE:
        n = [x for x in data[ph]['nodes'] if x['name'] == node]
        assert len(n) == 1
        d = n[0]['parameters']['toolDescription']
        for c in candidates:
            if c in d:
                pending += 1
                if not check:
                    d = d.replace(c, '')
        assert check or not any(c in d for c in candidates)
        assert not (' ADMIN la cambia' in d and not check), 'an ADMIN wording is still in %s' % node
        if not check:
            n[0]['parameters']['toolDescription'] = d
    if check:
        print('descriptions still to edit: %d' % pending)
        return 1 if pending else 0
    for p, f in FILES.items():
        with open(f, 'w', encoding='utf-8') as fh:
            fh.write(json.dumps(data[p], indent=2, ensure_ascii=False))
    print('edits applied: %d' % pending)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
