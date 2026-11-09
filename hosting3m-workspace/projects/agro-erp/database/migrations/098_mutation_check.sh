#!/usr/bin/env bash
# 098_mutation_check.sh: proves that the tests detect the loss of each protection.
# For each mutation it runs 098_tests.sql with one protection broken (inside the test transaction, always rolled back)
# and requires the run to FAIL on the expected assertion. M0 is the control: no mutation, the run must pass.
# LOCAL / throw-away schema only. Connection: standard libpq settings (PGHOST, PGPORT, PGUSER, PGDATABASE, ~/.pgpass).
set -u
cd "$(dirname "$0")"
PSQL="${PSQL:-psql} -X -v ON_ERROR_STOP=1"
fail=0
declare -A EXPECT=(
  [M1]='FAIL \[C1 '    # sale trigger removed
  [M2]='FAIL \[C10 '   # sp_solicitar_venta_orden loan blocks removed
  [M3]='FAIL \[B3 '    # unique index removed
  [M4]='FAIL \[B4 '    # P0100 guard neutralised
  [M5]='FAIL \[D2 '    # FIFO exclusion removed
  [M6]='FAIL \[F1 '    # DIED_AWAY trigger removed
)
out=$($PSQL -f 098_tests.sql 2>&1); rc=$?
if [ $rc -eq 0 ] && grep -q 'assertions passed' <<<"$out"; then echo "M0 control: PASS (no mutation, all assertions pass)"; else echo "M0 control: UNEXPECTED FAILURE"; echo "$out" | grep -E 'FAIL|ERROR' | head -3; fail=1; fi
for m in M1 M2 M3 M4 M5 M6; do
  out=$($PSQL -v mutation=$m -f 098_tests.sql 2>&1); rc=$?
  if [ $rc -ne 0 ] && grep -qE "${EXPECT[$m]}" <<<"$out"; then
    echo "$m: DETECTED -> $(grep -oE "FAIL \[[^]]*\]" <<<"$out" | head -1)"
  else
    echo "$m: NOT DETECTED (rc=$rc)"; echo "$out" | grep -E 'FAIL|ERROR' | head -3; fail=1
  fi
done
exit $fail
