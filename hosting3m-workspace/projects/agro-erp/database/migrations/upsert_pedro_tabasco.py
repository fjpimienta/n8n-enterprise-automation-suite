#!/usr/bin/env python3
"""
upsert_adult_cattle.py — Transcribed field-notebook adult cattle + palpation -> validated SQL.

USAGE
    python3 upsert_adult_cattle.py el_triunfo_palpacion.csv > 033_upsert_el_triunfo.sql

WHY THIS SHAPE
    Same rationale as load_birth_events.py: handwriting is too irregular to trust automated
    OCR for production data, so a human-transcribed staging CSV is validated here and
    converted to SQL, which then goes through the normal $LOCAL_DB / $PROD_DB gated
    workflow — clone first, verify, then production.

HOW THIS DIFFERS FROM load_birth_events.py
    That script inserts APPEND-ONLY birth records for calves that don't have a tag yet.
    This one is a real UPSERT into cattle_livestock: these are adult animals (cows, one
    bull) and calves that ALREADY carry their own SINIIGA tag. rfid_siniiga is UNIQUE in
    the schema, so ON CONFLICT (rfid_siniiga) DO UPDATE is the correct idempotent pattern —
    running this file twice updates the same rows instead of duplicating them, unlike
    load_birth_events.py which is deliberately NOT safe to re-run.

    Calves are linked to their dam via a subquery on the dam's rfid_siniiga (resolved at
    apply time, not at generation time — no fabricated UUIDs in the SQL). A palpation
    result becomes one row in cattle_health_logs (event_type='PALPACION'), guarded by a
    NOT EXISTS check on (livestock_id, event_type, event_date) so re-running the file does
    not create duplicate exam records for the same day.

WHAT THIS SCRIPT DELIBERATELY DOES NOT DO
    * It does NOT resolve a fecha_palpacion on its own. The source photos carry no visible
      exam date (unlike the birth-log notebooks, which do). A row without a date is an
      ERROR, not a default to today's date — inventing an exam date would misrepresent
      when the animal was actually seen.
    * It does NOT collapse an ambiguous UNE + follicle code on its own guesswork — but it
      DOES apply one explicit, client-confirmed rule: when the notebook shows "UNE"
      together with a follicle reading (e.g. "UNE IF15"), UNE prevails and the animal is
      recorded as VACIA (confirmed by the client 2026-08-04: "es preferible dejarla como
      Vacío... pero prevalece el UNE"). This only fires when the CSV's own
      resultado_normalizado is blank or REVISAR — an explicit value from the transcriber
      always wins over the automatic rule. The raw diagnostico_texto is preserved either way.
    * It does NOT compute birth_date from "edad declarada" (e.g. "05 años", "mes y medio").
      That's approximate age at the time of writing, not a birth date; inventing one would
      manufacture false precision. It is stored verbatim in metadata->>'edad_declarada'.

CSV COLUMNS (see el_triunfo_palpacion.csv for a filled example)
    tipo                  - SEMENTAL / VACA (case-insensitive)
    rfid_siniiga          - 10-digit tag, exactly as read (leading zero included)
    numero_fuego          - fire number as written
    fierro                - brand code (R / aR / etc.), matched against brand_registrations
    edad_declarada        - free text, stored verbatim in metadata, never used for math
    diagnostico_texto     - raw palpation finding, stored verbatim (required for VACA rows)
    resultado_normalizado - VACIA / GESTANTE_CONFIRMADA / PROBABLE_GESTANTE / CICLANDO /
                             REVISAR (required for VACA rows; ignored for SEMENTAL)
    cria_rfid             - tag of the calf at foot, if any and if already tagged (blank ok)
    cria_sexo             - MACHO / HEMBRA (required if cria_rfid is present)
    cria_edad_declarada   - free text, same treatment as edad_declarada
    fecha_palpacion       - DD/MM/YYYY — REQUIRED for every VACA row, no default
    confianza             - ALTA / MEDIA / BAJA (informational, not validated)
    revisar               - SI / blank (informational, not validated)
    notas                 - free text, carried through verbatim

EXIT BEHAVIOR
    Prints SQL to stdout, a validation report to stderr. Exits non-zero on any error row.
"""
import sys
import csv
import re
import json
from datetime import datetime
from collections import Counter

# Ranch/site name -> id_company. Reused convention from load_birth_events.py.
COMPANY_ALIASES = {
    "el triunfo": 6,          # Rancho El Triunfo, leased under UPP 54's tenant (Pedro)
    "puyacatengo": 6,         # UPP 54 / El Puyacatengo — Pedro's own registered unit
}
LEASED_SITE_NAME = "Rancho El Triunfo"
# Set to True when loading directly into Puyacatengo (a registered UPP) instead of a
# leased site. When True, production_unit_id is used instead of leased_site_id.
DIRECT_TO_REGISTERED_UNIT = True
SOURCE_LABEL = "Puyacatengo (UPP 54)"  # Used in health log descriptions; change per batch.

VALID_SEX = {"MACHO": "MACHO", "M": "MACHO", "HEMBRA": "HEMBRA", "H": "HEMBRA"}
VALID_RESULT = {
    "VACIA", "GESTANTE_CONFIRMADA", "PROBABLE_GESTANTE", "CICLANDO", "REVISAR"
}
DATE_FORMATS = ["%d/%m/%Y", "%d-%m-%Y", "%d/%m/%y", "%d-%m-%y"]


def apply_une_prevails_rule(diagnostico: str, resultado: str | None) -> tuple[str, bool]:
    """
    Client-confirmed rule (2026-08-04): when the notebook shows UNE (Útero Normal
    Estático — no follicular activity) together with a follicle reading (IF##/DF##,
    typically noise from a borderline exam or a trailing note about ovarian
    development observed anyway), UNE prevails. The animal is VACIA, full stop — the
    follicle size is retained in the raw diagnostico_texto for the record, but it does
    not change the reproductive status.

    Only fires when the transcriber left resultado_normalizado blank or as REVISAR —
    an explicit non-REVISAR value from the CSV always wins, this never overrides a
    human's deliberate call.
    """
    if resultado and resultado != "REVISAR":
        return resultado, False
    text = (diagnostico or "").upper()
    if "UNE" in text:
        return "VACIA", True
    return resultado or "REVISAR", False


def sql_quote(value):
    if value is None or str(value).strip() == "":
        return "NULL"
    escaped = str(value).replace("'", "''")
    return f"'{escaped}'"


def sql_jsonb_literal(d: dict) -> str:
    """
    Builds a valid SQL jsonb literal from a Python dict: '{"key": "value"}'::jsonb.

    BUG FIXED HERE (2026-08-04): the previous version hand-built JSON text using
    single-quoted values inside bare braces — e.g. {"edad_declarada": '05 años'}::jsonb —
    which is neither valid JSON (which requires double-quoted string values) nor a valid
    SQL literal (the whole blob was never wrapped in outer single quotes). Postgres saw a
    bare "{" sitting in the middle of a VALUES list and rejected it outright. This failed
    on EVERY row with metadata or a palpation result — nothing was silently wrong, the
    whole batch simply could not run, which is why it's caught immediately rather than
    partially loading bad data.

    Fix: json.dumps produces correct JSON (double-quoted, properly escaped), then the
    single quotes required to wrap it as a SQL string literal are escaped by doubling —
    the only special character JSON's own escaping doesn't already handle for us.
    """
    json_text = json.dumps(d, ensure_ascii=False)
    sql_escaped = json_text.replace("'", "''")
    return f"'{sql_escaped}'::jsonb"


def parse_date(raw: str, row_num: int, errors: list) -> str | None:
    raw = (raw or "").strip()
    if not raw:
        errors.append(
            f"Fila {row_num}: fecha_palpacion vacía. No se asume la fecha de hoy — "
            f"las fotos no traen fecha visible de examen, hay que confirmarla."
        )
        return None
    for fmt in DATE_FORMATS:
        try:
            dt = datetime.strptime(raw, fmt)
            if dt.year < 100:
                dt = dt.replace(year=2000 + dt.year)
            return dt.strftime("%Y-%m-%d")
        except ValueError:
            continue
    errors.append(f"Fila {row_num}: fecha_palpacion '{raw}' no reconocida (use DD/MM/YYYY)")
    return None


def validate_tag(raw: str, row_num: int, field_name: str, errors: list) -> str | None:
    raw = (raw or "").strip()
    if not raw:
        return None
    if not re.match(r"^\d{10}$", raw):
        errors.append(
            f"Fila {row_num}: {field_name} '{raw}' no tiene 10 dígitos "
            f"(formato SINIIGA confirmado: EE + 4 + 4)"
        )
        return None
    return raw


def main():
    if len(sys.argv) != 2:
        print(f"Uso: {sys.argv[0]} <archivo.csv>", file=sys.stderr)
        sys.exit(2)

    path = sys.argv[1]
    errors: list[str] = []
    warnings: list[str] = []
    rows_ok = []

    with open(path, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        required = {"tipo", "rfid_siniiga"}
        missing_cols = required - set(reader.fieldnames or [])
        if missing_cols:
            print(f"ERROR: faltan columnas obligatorias: {missing_cols}", file=sys.stderr)
            sys.exit(2)

        for i, row in enumerate(reader, start=2):
            tipo = (row.get("tipo") or "").strip().upper()
            if tipo not in ("SEMENTAL", "VACA", "NOVILLONA"):
                errors.append(f"Fila {i}: tipo '{row.get('tipo')}' debe ser SEMENTAL, VACA o NOVILLONA")
                continue

            rfid = validate_tag(row.get("rfid_siniiga"), i, "rfid_siniiga", errors)
            if rfid is None:
                continue

            fierro = (row.get("fierro") or "").strip() or None
            numero_fuego = (row.get("numero_fuego") or "").strip() or None
            edad = (row.get("edad_declarada") or "").strip() or None
            notas = (row.get("notas") or "").strip() or None

            diagnostico = (row.get("diagnostico_texto") or "").strip() or None
            resultado = (row.get("resultado_normalizado") or "").strip().upper() or None
            fecha_palpacion = None
            une_rule_applied = False

            row_error_count_before = len(errors)

            if tipo in ("VACA", "NOVILLONA"):
                if not diagnostico:
                    errors.append(f"Fila {i}: VACA sin diagnostico_texto")
                if resultado and resultado not in VALID_RESULT:
                    errors.append(
                        f"Fila {i}: resultado_normalizado '{resultado}' no es válido "
                        f"({', '.join(sorted(VALID_RESULT))})"
                    )
                else:
                    resultado, une_rule_applied = apply_une_prevails_rule(diagnostico, resultado)
                fecha_palpacion = parse_date(row.get("fecha_palpacion"), i, errors)

            cria_rfid = validate_tag(row.get("cria_rfid"), i, "cria_rfid", errors)
            cria_sexo_raw = (row.get("cria_sexo") or "").strip().upper()
            cria_sexo = None
            if cria_rfid:
                if cria_sexo_raw not in VALID_SEX:
                    errors.append(
                        f"Fila {i}: cria_rfid presente pero cria_sexo '{row.get('cria_sexo')}' "
                        f"no es MACHO/HEMBRA/M/H"
                    )
                else:
                    cria_sexo = VALID_SEX[cria_sexo_raw]
            cria_edad = (row.get("cria_edad_declarada") or "").strip() or None

            # BUG FIXED (2026-08-04): errors accumulated above (missing diagnostico, bad
            # resultado, missing/bad fecha_palpacion, bad cria_sexo) used to be logged but
            # NEVER caused the row to be skipped — the animal upsert and even a palpation
            # health log with event_date=NULL still made it into the generated SQL. A row
            # for arete 0721391943 with a deliberately blank fecha_palpacion (used to force
            # exclusion pending client confirmation of a suspected re-tagging conflict)
            # was reported as "1 error" in the summary but STILL got INSERTed. Any error
            # on this row now means the row is skipped entirely, matching what the tipo/
            # rfid checks already did further up.
            if len(errors) > row_error_count_before:
                continue

            rows_ok.append({
                "line": i, "tipo": tipo, "rfid": rfid, "fierro": fierro,
                "numero_fuego": numero_fuego, "edad": edad, "notas": notas,
                "diagnostico": diagnostico, "resultado": resultado,
                "une_rule_applied": une_rule_applied,
                "fecha_palpacion": fecha_palpacion,
                "cria_rfid": cria_rfid, "cria_sexo": cria_sexo, "cria_edad": cria_edad,
            })

    # Duplicate tag check within the file itself.
    seen = Counter(r["rfid"] for r in rows_ok)
    for rfid, count in seen.items():
        if count > 1:
            warnings.append(f"Arete {rfid} aparece {count} veces en el CSV — revisar antes de aplicar.")

    # -----------------------------------------------------------------------
    # SQL generation
    # -----------------------------------------------------------------------
    id_company = COMPANY_ALIASES["puyacatengo"]
    sql = [
        "-- Generated by upsert_adult_cattle.py — DO NOT EDIT BY HAND, regenerate instead.",
        f"-- Source file: {path}",
        f"-- Valid rows: {len(rows_ok)}",
        "--",
        "-- Safe to re-run: upserts by rfid_siniiga (UNIQUE), and palpation events are",
        "-- guarded by NOT EXISTS on (livestock_id, event_type, event_date).",
        "BEGIN;",
        "",
    ]

    leased_site_subq = (
        f"(SELECT id FROM leased_land_sites WHERE id_company = {id_company} "
        f"AND upper(site_name) = upper({sql_quote(LEASED_SITE_NAME)}) LIMIT 1)"
    )
    registered_unit_subq = (
        f"(SELECT id FROM production_units WHERE id_company = {id_company} "
        f"AND is_active = true LIMIT 1)"
    )
    location_column = "production_unit_id" if DIRECT_TO_REGISTERED_UNIT else "leased_site_id"
    location_subq = registered_unit_subq if DIRECT_TO_REGISTERED_UNIT else leased_site_subq

    for r in rows_ok:
        brand_subq = "NULL"
        if r["fierro"]:
            brand_subq = (
                f"(SELECT id FROM brand_registrations "
                f"WHERE upper(brand_code) = upper({sql_quote(r['fierro'])}) LIMIT 1)"
            )

        category = "TORO" if r["tipo"] == "SEMENTAL" else r["tipo"]
        business_model = "REPRODUCCION" if r["tipo"] == "SEMENTAL" else "CRIA"

        metadata_dict = {}
        if r["edad"]:
            metadata_dict["edad_declarada"] = r["edad"]
        if r["notas"]:
            metadata_dict["nota_transcripcion"] = r["notas"]
        # current_weight_kg is NOT NULL in production (discovered 2026-08-04, not in the
        # documented schema). These notebooks record no weight at all — only age and
        # palpation. Rather than fabricate a number, insert 0 and flag it explicitly so
        # any weight-based report (biomass totals, ADG) can filter these rows out instead
        # of silently averaging in a false zero.
        metadata_dict["peso_no_registrado"] = True
        metadata_literal = sql_jsonb_literal(metadata_dict)

        sql.append(f"-- Fila {r['line']} · {r['tipo']} · arete {r['rfid']}")
        sql.append(
            "INSERT INTO cattle_livestock "
            f"(tenant_id, rfid_siniiga, numero_fuego, category, business_model, "
            f"current_status, species, current_weight_kg, brand_id, {location_column}, metadata) VALUES ("
            f"{id_company}, {sql_quote(r['rfid'])}, {sql_quote(r['numero_fuego'])}, "
            f"{sql_quote(category)}, {sql_quote(business_model)}, 'ACTIVO', 'BOVINO', 0, "
            f"{brand_subq}, {location_subq}, {metadata_literal}"
            ")"
        )

        if DIRECT_TO_REGISTERED_UNIT:
            location_set_clause = (
                "production_unit_id = COALESCE(cattle_livestock.production_unit_id, EXCLUDED.production_unit_id), "
            )
        else:
            # Never relocate an animal that already has a REGISTERED production unit — a
            # notebook transcription must not override a curated UPP assignment. Found in
            # production 2026-08-04: the semental (2718322064) already lived in UPP 54's
            # real production_units row (birth_date, weight, metadata all populated by an
            # earlier load) when this same bull also turned up in the El Triunfo notebook.
            # leased_site_id is only ever set for animals with NO production_unit_id yet.
            location_set_clause = (
                "leased_site_id = CASE "
                "  WHEN cattle_livestock.production_unit_id IS NOT NULL THEN cattle_livestock.leased_site_id "
                "  ELSE COALESCE(cattle_livestock.leased_site_id, EXCLUDED.leased_site_id) "
                "END, "
            )

        # FINDING (2026-08-05): cross-referencing this notebook against the 21
        # NOVILLO/VACÍA records already flagged as a data-quality defect (round
        # placeholder weights, no numero_fuego, category/status that never made sense
        # for a supposedly male animal) showed 12 of 24 tags overlap exactly. This
        # notebook is very likely the correct source data for that defective batch, not
        # a separate herd. So: when the EXISTING row's category is the placeholder
        # 'NOVILLO', the real category from this notebook overrides it. This condition
        # is deliberately narrow — it only fires on the exact defect signature, never on
        # an animal that was genuinely, correctly tagged TORO/NOVILLO elsewhere.
        category_correction = (
            "category = CASE WHEN cattle_livestock.category = 'NOVILLO' "
            "THEN EXCLUDED.category ELSE cattle_livestock.category END, "
        )

        sql.append(
            "ON CONFLICT (rfid_siniiga) DO UPDATE SET "
            "numero_fuego = COALESCE(EXCLUDED.numero_fuego, cattle_livestock.numero_fuego), "
            "brand_id = COALESCE(EXCLUDED.brand_id, cattle_livestock.brand_id), "
            + category_correction
            + location_set_clause +
            "metadata = cattle_livestock.metadata || EXCLUDED.metadata;"
        )

        if r["tipo"] in ("VACA", "NOVILLONA") and r["diagnostico"]:
            medicines_literal = sql_jsonb_literal({
                "resultado": r["diagnostico"],
                "resultado_normalizado": r["resultado"] or "REVISAR",
            })
            sql.append(
                "INSERT INTO cattle_health_logs "
                "(livestock_id, event_type, description, medicines_json, event_date) "
                "SELECT cl.id, 'PALPACION', "
                f"{sql_quote(f'Palpación transcrita de libreta de campo — {SOURCE_LABEL}')}, "
                f"{medicines_literal}, {sql_quote(r['fecha_palpacion'])} "
                "FROM cattle_livestock cl "
                f"WHERE cl.rfid_siniiga = {sql_quote(r['rfid'])} "
                "AND NOT EXISTS ("
                "  SELECT 1 FROM cattle_health_logs h "
                "  WHERE h.livestock_id = cl.id AND h.event_type = 'PALPACION' "
                f"   AND h.event_date::date = {sql_quote(r['fecha_palpacion'])}"
                ");"
            )

        if r["cria_rfid"]:
            calf_category = "BECERRO" if r["cria_sexo"] == "MACHO" else "BECERRA"
            calf_metadata_dict = {}
            if r["cria_edad"]:
                calf_metadata_dict["edad_declarada"] = r["cria_edad"]
            calf_metadata_dict["peso_no_registrado"] = True
            calf_metadata_literal = sql_jsonb_literal(calf_metadata_dict)

            sql.append(
                "INSERT INTO cattle_livestock "
                "(tenant_id, rfid_siniiga, category, business_model, current_status, "
                "species, current_weight_kg, mother_id, leased_site_id, metadata) "
                "SELECT "
                f"{id_company}, {sql_quote(r['cria_rfid'])}, {sql_quote(calf_category)}, "
                f"'CRIA', 'ACTIVO', 'BOVINO', 0, cl.id, {leased_site_subq}, "
                f"{calf_metadata_literal} "
                "FROM cattle_livestock cl "
                f"WHERE cl.rfid_siniiga = {sql_quote(r['rfid'])} "
                "ON CONFLICT (rfid_siniiga) DO UPDATE SET "
                "mother_id = COALESCE(cattle_livestock.mother_id, EXCLUDED.mother_id), "
                "leased_site_id = CASE "
                "  WHEN cattle_livestock.production_unit_id IS NOT NULL THEN cattle_livestock.leased_site_id "
                "  ELSE COALESCE(cattle_livestock.leased_site_id, EXCLUDED.leased_site_id) "
                "END, "
                "metadata = cattle_livestock.metadata || EXCLUDED.metadata;"
            )

        sql.append("")

    sql.append("COMMIT;")
    print("\n".join(sql))

    # -----------------------------------------------------------------------
    # Report
    # -----------------------------------------------------------------------
    n_revisar = sum(1 for r in rows_ok if r.get("resultado") == "REVISAR")
    n_une_rule = sum(1 for r in rows_ok if r.get("une_rule_applied"))
    print("", file=sys.stderr)
    print("=" * 70, file=sys.stderr)
    print(f"Filas válidas: {len(rows_ok)}", file=sys.stderr)
    print(f"Errores: {len(errors)}", file=sys.stderr)
    print(f"Advertencias: {len(warnings)}", file=sys.stderr)
    print(f"Resueltas automáticamente por regla 'UNE prevalece': {n_une_rule}", file=sys.stderr)
    print(f"Diagnósticos que siguen en REVISAR: {n_revisar}", file=sys.stderr)
    print("=" * 70, file=sys.stderr)

    if errors:
        print("\nERRORES (filas excluidas del SQL generado):", file=sys.stderr)
        for e in errors:
            print(f"  ✘ {e}", file=sys.stderr)

    if warnings:
        print("\nADVERTENCIAS:", file=sys.stderr)
        for w in warnings:
            print(f"  ⚠ {w}", file=sys.stderr)

    if n_revisar:
        print(
            f"\n⚠ {n_revisar} vacas quedaron con resultado_normalizado = REVISAR. "
            f"Se cargan con su diagnóstico crudo intacto, pero NO se puede saber si están "
            f"vacías o ciclando hasta que el veterinario confirme el código real.",
            file=sys.stderr
        )

    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
