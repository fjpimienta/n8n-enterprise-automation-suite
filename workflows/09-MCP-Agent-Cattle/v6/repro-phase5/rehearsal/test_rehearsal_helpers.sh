#!/usr/bin/env bash
# test_rehearsal_helpers.sh — OFFLINE tests of the pure helpers of rehearsal_lib.sh.
# No docker and no database are used: it reads the repo files and writes only to a throwaway folder (REHEARSAL_OUT, default a mktemp folder).
# The two guard tests call guard_local only on paths that refuse BEFORE the first docker call (no flag; flag with an invalid database name).
# Usage:   bash test_rehearsal_helpers.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export REHEARSAL_OUT="${REHEARSAL_OUT:-$(mktemp -d)}"
mkdir -p "$REHEARSAL_OUT"
unset REHEARSAL_DB
. "$HERE/rehearsal_lib.sh"
pass=0; fail=0
ok()  { echo "PASS  $1"; pass=$((pass + 1)); }
bad() { echo "FAIL  $1"; fail=$((fail + 1)); }

# 1. the variables block is extracted from the runbook and parses
if extract_vars_block; then ok "variables block extracted from the runbook and passes bash -n ($(wc -l < "$REH_OUT/repro_vars.sh") lines)"; else bad "extract_vars_block"; fi
( . "$REH_OUT/repro_vars.sh"; [ "$COMMIT_BEFORE_PHASE5" = 14dd60c ] && [ "$P" = "$PRODUCTION_P" ] ) \
  && ok "sourcing it gives COMMIT_BEFORE_PHASE5=14dd60c and the production P string the rehearsal expects" || bad "sourced values"

# 2. need() from the runbook block
( set -u; . "$REH_OUT/repro_vars.sh"
  t() { ( OWNER_TEST="$1"; need OWNER_TEST ) >/dev/null 2>&1; }
  lt="$(printf '\074')"
  if t ""; then exit 1; fi; if t "${lt}FILL: x"; then exit 2; fi; if t "FILL later"; then exit 3; fi
  if ( unset OWNER_TEST; need OWNER_TEST ) >/dev/null 2>&1; then exit 4; fi
  t "a real value" || exit 5 ) && ok "need(): rejects empty, angle-bracket, FILL and unset values; accepts a real one" || bad "need() self test (exit $?)"

# 3. md5 table of the runbook against the real files, and a corrupted copy
out="$(check_md5_table 2>&1)"; rc=$?
echo "$out" | tail -1
[ $rc = 0 ] && ok "md5 table: the 23 files of 084-090 match the runbook" || bad "md5 table"
cp "$RUNBOOK" "$REH_OUT/runbook_copy.md"
python3 - "$REH_OUT/runbook_copy.md" <<'PY'
import sys, re
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
m = re.search(r"(\| `090_rollback.sql` \| `)([0-9a-f])", s)
s = s[:m.start(2)] + ('0' if m.group(2) != '0' else '1') + s[m.end(2):]
open(p, 'w', encoding='utf-8').write(s)
PY
( RUNBOOK="$REH_OUT/runbook_copy.md"; check_md5_table ) >/dev/null 2>&1 && bad "md5 check accepted a corrupted table" || ok "md5 check fails when one digit of the table is wrong"

# 4. fingerprints
printf 'x\n=== FINGERPRINTS (must not change)\n a | 1\n b | 2\n c | 3\n(3 rows)\n\n=== BODY_\n d | 9\n' > "$REH_OUT/fp_a.txt"
printf 'y\n=== FINGERPRINTS (must not change)\n a | 1\n b | 2\n c | 3\n(3 rows)\n\n=== BODY_\n d | 8\n' > "$REH_OUT/fp_b.txt"
printf 'y\n=== FINGERPRINTS (must not change)\n a | 1\n b | 2\n c | 4\n(3 rows)\n\n=== BODY_\n' > "$REH_OUT/fp_c.txt"
printf 'nothing here\n' > "$REH_OUT/fp_d.txt"
fingerprints_equal "$REH_OUT/fp_a.txt" "$REH_OUT/fp_b.txt" >/dev/null && ok "fingerprints equal although the BODY section differs" || bad "fingerprints_equal (equal case)"
fingerprints_equal "$REH_OUT/fp_a.txt" "$REH_OUT/fp_c.txt" >/dev/null && bad "fingerprints_equal accepted a changed row" || ok "fingerprints_equal fails when one fingerprint row differs"
fingerprints_equal "$REH_OUT/fp_d.txt" "$REH_OUT/fp_d.txt" >/dev/null && bad "fingerprints_equal accepted an output with no section" || ok "fingerprints_equal fails when the section is missing"

# 5. run_step
okfn()   { echo hello; }
skipfn() { echo "REHEARSAL_SKIP: nothing to do"; }
sefn()   { false; echo "this line must NOT print"; }
( run_step t_ok okfn; run_step t_skip skipfn; echo "R=${STEP_RESULTS[*]}" ) 2>&1 | grep -q "R=OK SKIP" && ok "run_step records OK and SKIP" || bad "run_step OK/SKIP"
( run_step t_fail sefn; echo "REACHED-AFTER-FAIL" ) > "$REH_OUT/rs_out.txt" 2>&1; rc=$?
if [ $rc = 1 ] && ! grep -q REACHED-AFTER-FAIL "$REH_OUT/rs_out.txt" && ! grep -q "must NOT print" "$REH_OUT"/*_t_fail.txt; then
  ok "run_step: set -e is active inside the body, a failing step stops the script (exit 1)"
else bad "run_step FAIL semantics (rc=$rc)"; fi
( refuse "test" ) >/dev/null 2>&1; [ $? = 2 ] && ok "refuse() exits with 2" || bad "refuse() exit code"

# 6. REHEARSAL_DB validation (pure function)
for good in hosting3m_rehearsal hosting3m_rehearsal2 hosting3m_a_1 hosting3m_x; do
  validate_rehearsal_db "$good" 2>/dev/null && ok "REHEARSAL_DB accepted: $good" || bad "REHEARSAL_DB rejected a good name: $good"
done
nl="$(printf 'hosting3m_x\nhosting3m_y')"
for badname in postgres template0 template1 hosting3m_db "hosting3m_x y" "hosting3m_x;y" "hosting3m_x;DROP" "hosting3m_" "Hosting3m_x" "hosting3m_X" "hosting3m_x'y" "hosting3m_x-y" "../hosting3m_x" "hosting3m_x/y" "" "$nl" "hosting3m_x\$(id)"; do
  if validate_rehearsal_db "$badname" 2>/dev/null; then bad "REHEARSAL_DB accepted a bad name: '$badname'"; else ok "REHEARSAL_DB rejected: '$(printf '%s' "$badname" | tr '\n' '|')'"; fi
done
msg="$(validate_rehearsal_db hosting3m_db 2>&1)"
echo "$msg" | grep -q "NOT a clean base" && ok "the hosting3m_db message says it is not a clean base and points at the README" || bad "hosting3m_db message"
( unset REHEARSAL_DB; . "$HERE/rehearsal_lib.sh"; [ "$REHEARSAL_DB" = hosting3m_db ] && ! validate_rehearsal_db "$REHEARSAL_DB" 2>/dev/null ) \
  && ok "the DEFAULT (hosting3m_db) is refused: the run needs REHEARSAL_DB set to a fresh database" || bad "default REHEARSAL_DB"

# 7. guard_local on the paths that refuse before any docker call
( guard_local ) >/dev/null 2>&1; [ $? = 2 ] && ok "guard_local without --i-know-this-is-local refuses (exit 2)" || bad "guard without the flag"
for badname in hosting3m_db postgres "x;y"; do
  ( REHEARSAL_DB="$badname"; guard_local --i-know-this-is-local ) >/dev/null 2>&1
  [ $? = 2 ] && ok "guard_local with the flag and REHEARSAL_DB='$badname' refuses (exit 2) before any docker call" || bad "guard with REHEARSAL_DB='$badname'"
done
( LOCAL_P=""; REHEARSAL_DB=hosting3m_rehearsal; load_vars ) >/dev/null 2>&1; [ $? = 2 ] && ok "load_vars refuses when guard_local has not built P" || bad "load_vars without the guard"

echo; echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
