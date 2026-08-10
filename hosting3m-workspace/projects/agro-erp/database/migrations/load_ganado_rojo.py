#!/usr/bin/env python3
"""
load_ganado_rojo.py — Bulk inventory sheet (201 head, "Sociedad Ganado Rojo",
Droughtmaster) -> validated SQL.

WHY THIS IS A SEPARATE SCRIPT, NOT A REUSE OF upsert_adult_cattle.py
    That script assumes every row has a palpation diagnosis and possibly a tagged
    calf. This sheet is pure inventory: no palpation data, no calves, and — critically
    — 74% of the animals (148 of 201) have no SINIIGA tag at all. The identity strategy
    is fundamentally different here, so forcing this shape into that script would have
    meant bolting on more special cases than writing a focused one.

IDENTITY STRATEGY (read before changing)
    * Tagged animals (52 of 201, rfid_siniiga present): upserted via
      ON CONFLICT (rfid_siniiga) — safe to re-run, matches the pattern used everywhere
      else in this project.
    * Untagged animals (149 of 201, including one whose transcribed tag was malformed
      and is treated as untagged — see CSV row 2): INSERT ONLY. There is no reliable
      natural key. numero_fuego is NOT used as a merge key because the client has
      explicitly confirmed it can legitimately repeat by capture error (see
      vw_duplicate_fire_numbers, migration 030) — building an upsert on top of a key
      that is allowed to collide would silently merge two different animals into one
      row on a re-run. This script is therefore NOT SAFE TO RE-RUN for untagged rows,
      exactly like load_birth_events.py, and says so loudly in the generated SQL header.

LOCATION (deliberately left unset)
    Client confirmed (2026-08-05): all 201 animals belong to "La Bendición" but may
    stand on any of Alejandro's 3 registered units. Guessing a specific
    production_unit_id would misrepresent data nobody actually verified per-animal.
    Both production_unit_id and leased_site_id are left NULL — this is schema-legal
    (the mutual-exclusion CHECK only forbids both being NON-null at once) and simply
    means "location not yet assigned", to be resolved later, not guessed now.

WEIGHT (same NOT NULL workaround as upsert_adult_cattle.py)
    current_weight_kg is NOT NULL in production with no documented default. This sheet
    carries no weights at all. Inserted as 0 with metadata.peso_no_registrado = true so
    any biomass report can filter these rows out instead of averaging in a false zero.

BREED
    Client confirmed (2026-08-05): raza Droughtmaster (DM). There is no breed_id column
    on cattle_livestock and cattle_breed_catalog is an unrelated global standards table
    (target weights/gestation), not a per-animal FK target as of this migration set.
    Stored as metadata.raza — the same "don't invent schema you haven't confirmed you
    need" judgment call already made for edad_declarada elsewhere in this project.

USAGE
    python3 load_ganado_rojo.py ganado_rojo.csv > 034_load_ganado_rojo.sql
"""
import sys
import csv
import json
import re
from collections import Counter


def sql_quote(value):
    if value is None or str(value).strip() == "":
        return "NULL"
    escaped = str(value).replace("'", "''")
    return f"'{escaped}'"


def sql_jsonb_literal(d: dict) -> str:
    json_text = json.dumps(d, ensure_ascii=False)
    sql_escaped = json_text.replace("'", "''")
    return f"'{sql_escaped}'::jsonb"


ID_COMPANY = 5  # "La Bendición" (San José y La Pita), confirmed by client 2026-08-05
BRAND_CODE_DEFAULT = "R"
BREED_LABEL = "Droughtmaster (DM)"


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
        required = {"fila", "numero_fuego", "categoria", "fierro"}
        missing_cols = required - set(reader.fieldnames or [])
        if missing_cols:
            print(f"ERROR: faltan columnas obligatorias: {missing_cols}", file=sys.stderr)
            sys.exit(2)

        for row in reader:
            fila = row.get("fila", "?")
            arete = (row.get("arete_siniiga") or "").strip() or None
            fuego = (row.get("numero_fuego") or "").strip() or None
            categoria = (row.get("categoria") or "").strip().upper()
            fierro = (row.get("fierro") or "").strip() or BRAND_CODE_DEFAULT
            notas = (row.get("notas") or "").strip() or None

            if not fuego:
                errors.append(f"Fila {fila}: sin numero_fuego — no hay forma de identificar el animal")
                continue

            if categoria not in ("VACA", "TORO"):
                errors.append(f"Fila {fila}: categoria '{categoria}' debe ser VACA o TORO")
                continue

            if arete and not re.match(r"^\d{10}$", arete):
                errors.append(
                    f"Fila {fila}: arete_siniiga '{arete}' no tiene 10 dígitos — "
                    f"déjalo en blanco para cargar solo por quemado, o corrígelo"
                )
                continue

            rows_ok.append({
                "fila": fila, "arete": arete, "fuego": fuego,
                "categoria": categoria, "fierro": fierro, "notas": notas,
            })

    # Duplicate checks, split by risk level.
    tagged = [r for r in rows_ok if r["arete"]]
    untagged = [r for r in rows_ok if not r["arete"]]

    dup_tags = Counter(r["arete"] for r in tagged)
    for tag, count in dup_tags.items():
        if count > 1:
            errors.append(f"Arete {tag} aparece {count} veces — esto SÍ es un error real, corrígelo antes de cargar.")

    dup_fuego_untagged = Counter(r["fuego"] for r in untagged)
    for fuego, count in dup_fuego_untagged.items():
        if count > 1:
            warnings.append(
                f"Quemado {fuego} se repite {count} veces entre animales SIN arete — "
                f"sin forma de distinguirlos, se cargan como filas separadas. Verificar en campo."
            )

    dup_fuego_tagged = Counter(r["fuego"] for r in tagged)
    for fuego, count in dup_fuego_tagged.items():
        if count > 1:
            warnings.append(
                f"Quemado {fuego} se repite {count} veces entre animales CON arete distinto — "
                f"sin conflicto real (cada uno tiene su propio arete), es la reutilización de "
                f"quemado que el cliente ya confirmó que puede pasar."
            )

    if errors:
        print(f"\nERRORES ({len(errors)}):", file=sys.stderr)
        for e in errors:
            print(f"  ✘ {e}", file=sys.stderr)

    # -----------------------------------------------------------------------
    # SQL generation
    # -----------------------------------------------------------------------
    sql = [
        "-- Generated by load_ganado_rojo.py — DO NOT EDIT BY HAND, regenerate instead.",
        f"-- Source file: {path}",
        f"-- Total rows: {len(rows_ok)} ({len(tagged)} con arete, {len(untagged)} sin arete)",
        "--",
        "-- ⚠️ NOT SAFE TO RE-RUN. Tagged animals upsert safely via rfid_siniiga (UNIQUE).",
        "-- Untagged animals (INSERT only, no natural key) WILL duplicate if this file runs",
        "-- twice against the same environment. Same caution as load_birth_events.py.",
        "--",
        "-- production_unit_id and leased_site_id are left NULL for all 201 animals:",
        "-- client confirmed (2026-08-05) these belong to 'La Bendición' but could stand",
        "-- on any of Alejandro's 3 registered units. Not guessed here.",
        "BEGIN;",
        "",
    ]

    brand_subq_cache = {}

    def brand_subq(code):
        if code not in brand_subq_cache:
            brand_subq_cache[code] = (
                f"(SELECT id FROM brand_registrations WHERE upper(brand_code) = upper({sql_quote(code)}) LIMIT 1)"
            )
        return brand_subq_cache[code]

    for r in rows_ok:
        category = r["categoria"]
        business_model = "REPRODUCCION" if category == "TORO" else "CRIA"
        metadata = {"raza": BREED_LABEL, "peso_no_registrado": True}
        if r["notas"]:
            metadata["nota_transcripcion"] = r["notas"]
        metadata_literal = sql_jsonb_literal(metadata)

        sql.append(f"-- Fila {r['fila']} · {category} · fuego {r['fuego']}"
                    + (f" · arete {r['arete']}" if r["arete"] else " · SIN ARETE"))

        if r["arete"]:
            sql.append(
                "INSERT INTO cattle_livestock "
                "(tenant_id, rfid_siniiga, numero_fuego, category, business_model, "
                "current_status, species, current_weight_kg, brand_id, metadata) VALUES ("
                f"{ID_COMPANY}, {sql_quote(r['arete'])}, {sql_quote(r['fuego'])}, "
                f"{sql_quote(category)}, {sql_quote(business_model)}, 'ACTIVO', 'BOVINO', 0, "
                f"{brand_subq(r['fierro'])}, {metadata_literal}"
                ") "
                "ON CONFLICT (rfid_siniiga) DO UPDATE SET "
                "numero_fuego = EXCLUDED.numero_fuego, "
                "brand_id = COALESCE(EXCLUDED.brand_id, cattle_livestock.brand_id), "
                "metadata = cattle_livestock.metadata || EXCLUDED.metadata;"
            )
        else:
            # rfid_siniiga is NOT NULL in production (discovered 2026-08-08, undocumented —
            # same category of surprise as current_weight_kg in migration 024). Cannot insert
            # a literal NULL for the 149 untagged animals the client explicitly asked to load
            # by quemado alone. Reusing the S/N-<fuego>-<consecutivo> placeholder convention
            # ALREADY established in production for the original 21 untagged La Bendición
            # animals (see cattle_livestock rows like 'S/N-1534-936') rather than inventing a
            # new pattern. Appending the CSV row number guarantees uniqueness even for the two
            # confirmed duplicate quemados (1901, 1870) — each gets its own placeholder.
            # fn_has_official_ear_tag() already rejects anything starting with 'S/N', so these
            # correctly read as "no official tag" everywhere movement-readiness is evaluated.
            placeholder_tag = f"S/N-{r['fuego']}-{r['fila']}"
            sql.append(
                "INSERT INTO cattle_livestock "
                "(tenant_id, rfid_siniiga, numero_fuego, category, business_model, "
                "current_status, species, current_weight_kg, brand_id, metadata) VALUES ("
                f"{ID_COMPANY}, {sql_quote(placeholder_tag)}, {sql_quote(r['fuego'])}, "
                f"{sql_quote(category)}, {sql_quote(business_model)}, 'ACTIVO', 'BOVINO', 0, "
                f"{brand_subq(r['fierro'])}, {metadata_literal}"
                ");"
            )
        sql.append("")

    sql.append("COMMIT;")
    print("\n".join(sql))

    print("", file=sys.stderr)
    print("=" * 70, file=sys.stderr)
    print(f"Filas válidas: {len(rows_ok)} ({len(tagged)} con arete, {len(untagged)} sin arete)", file=sys.stderr)
    print(f"Errores: {len(errors)}", file=sys.stderr)
    print(f"Advertencias: {len(warnings)}", file=sys.stderr)
    print("=" * 70, file=sys.stderr)
    if warnings:
        print("\nADVERTENCIAS (revisar, no bloquean la carga):", file=sys.stderr)
        for w in warnings:
            print(f"  ⚠ {w}", file=sys.stderr)

    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
