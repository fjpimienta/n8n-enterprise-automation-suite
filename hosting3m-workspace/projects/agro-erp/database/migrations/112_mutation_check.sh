#!/usr/bin/env bash
# 112_mutation_check.sh: proves that the 112 tests notice the loss of each rule.
# M0 is the control (no mutation: all assertions pass). Every other run breaks ONE thing in a copy of the function inside the test transaction (always rolled back;
# the files are never changed) and the tests must then fail:
#   M1 tonne factor            M2 per-concept tolerance (1 cent)     M3 subtotal tolerance too loose (n)      M4 subtotal tolerance too strict (n-2)
#   M5 unit allow-list         M6 mixed units allowed                M7 mixed product keys allowed            M8 duplicate tickets allowed
#   M9 concept cap (10 -> 11)  M10 price per kilogram from the total M11 non-positive quantities allowed      M12 kilogram cap removed
#   M13 quantity not summed    M14 ticket lookup in the detail off   M15 detail loses the original unit       M16 ticket_ref is the last ticket
#   M17 no warning without ticket   M18 zero concepts allowed
#   G1 detail guard: kilograms not compared      G2 amounts not compared      G3 duplicate tickets in the detail   G4 invalid element not counted
#   G5 several concepts without detail allowed   G6 element without kg / amount_cents ignored in the sums
# LOCAL / throw-away database only. Connection: standard libpq settings (PGHOST, PGPORT, PGUSER, PGDATABASE, ~/.pgpass), or PSQL="docker exec -i -w /tmp/m ... psql ..."
# (with the 104_*, 105_*, 112_* files copied to that directory). A run that stops because the mutation did not change the text is reported as INVALID, not as killed.
set -u
cd "$(dirname "$0")"
PSQL="${PSQL:-psql} -X -v ON_ERROR_STOP=1"
fail=0; killed=0; survived=0
out=$($PSQL -v mutation=none -f 112_tests.sql 2>&1); rc=$?
if [ $rc -eq 0 ] && grep -q 'assertions passed' <<<"$out"; then echo "M0 control: PASS ($(grep -o '[0-9]* assertions passed' <<<"$out"))"; else echo "M0 control: UNEXPECTED FAILURE"; echo "$out" | tail -5; exit 1; fi
for m in M1 M2 M3 M4 M5 M6 M7 M8 M9 M10 M11 M12 M13 M14 M15 M16 M17 M18 G1 G2 G3 G4 G5 G6; do
  out=$($PSQL -v mutation=$m -f 112_tests.sql 2>&1); rc=$?
  if grep -q 'did not change the function\|unknown mutation' <<<"$out"; then
    echo "$m: INVALID MUTATION ($(grep -oE 'mutation [A-Z0-9]+ did not change the function|unknown mutation [A-Z0-9]+' <<<"$out" | head -1))"; fail=1
  elif [ $rc -ne 0 ] && grep -qE 'ERROR' <<<"$out"; then
    echo "$m: KILLED -> $(grep -oE 'ERROR:  [^"]{0,90}' <<<"$out" | head -1)"; killed=$((killed + 1))
  else
    echo "$m: SURVIVED (rc=$rc)"; fail=1; survived=$((survived + 1))
  fi
done
echo "112 mutation check: $killed killed, $survived survived"
exit $fail
