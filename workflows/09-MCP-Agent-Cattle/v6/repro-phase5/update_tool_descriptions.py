#!/usr/bin/env python3
"""Phase 5 - edits ONLY the `toolDescription` text of some nodes in the repro-phase1..4 tool files.

Why: the descriptions written in phases 1-4 predate the owner's decisions (confirmation levels) and migration 090:
  * NIVEL 2 tools (log_empadre_entry, log_empadre_entry_batch, log_palpation_with_condition, register_birth_checked) must NOT ask for
    a Si/No before running; NIVEL 3 tools (void_empadre_entry, births_batch_register, register_historical_birth, void_historical_birth)
    keep that sentence.
  * three descriptions say an ADMIN changes settings / codes "from the panel": there is no panel, it is SQL.
  * the palpation description must teach the 090 answers (not_examined, needs_explicit_result, vet_flag ...).
Every replacement must match EXACTLY ONCE (the script aborts otherwise) and nothing but `toolDescription` is touched.
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
    (4, 'get_births_config',
     'Solo un ADMIN la cambia desde el panel; tú no puedes cambiarla.',
     'Solo un ADMIN la cambia por SQL (no hay pantalla); tú no puedes cambiarla.'),
]


def main(argv):
    check = '--check' in argv
    data = {p: json.load(open(f, encoding='utf-8')) for p, f in FILES.items()}
    pending = 0
    for ph, node, old, new in EDITS:
        n = [x for x in data[ph]['nodes'] if x['name'] == node]
        assert len(n) == 1, 'node %s not found exactly once in phase %d' % (node, ph)
        d = n[0]['parameters']['toolDescription']
        if old in d:
            assert d.count(old) == 1, 'replacement matches more than once in %s' % node
            pending += 1
            if not check:
                n[0]['parameters']['toolDescription'] = d.replace(old, new)
        elif new.strip() and new in d:
            continue                                     # already applied
        else:
            raise SystemExit('ABORT: neither the old nor the new text is in %s (edited by hand?)' % node)
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
