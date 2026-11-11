#!/usr/bin/env bash
# 099_mutation_check.sh: proves that 099_tests.sql detects the loss of each protection.
# For each mutation it runs 099_tests.sql with one protection broken (inside the test transaction, always rolled back)
# and requires the run to FAIL on the expected assertion. M0 is the control: no mutation, the run must pass.
# LOCAL / throw-away schema only. Connection: standard libpq settings (PGHOST, PGPORT, PGUSER, PGDATABASE, ~/.pgpass).
set -u
cd "$(dirname "$0")"
PSQL="${PSQL:-psql} -X -v ON_ERROR_STOP=1"
fail=0
declare -A EXPECT=(
  [M1]='FAIL \[B5 '     # UPP code of any company resolves
  [M2]='FAIL \[C2 '     # lot not limited to the resolved UPP
  [M3]='FAIL \[G1 '     # purchase price 0 accepted
  [M4]='FAIL \[D3 '     # no placeholder detection
  [M5]='FAIL \[F1 '     # a preview writes
  [M6]='FAIL \[A2 '     # membership not required
  [M7]='FAIL \[A5 '     # palm accepted
  [M8]='FAIL \[E5 '     # other companies' tags not checked
  [M9]='FAIL \[F2 '     # commit without preview_hash
  [M10]='FAIL \[A3 '    # CUSTOMER allowed
  [M11]='FAIL \[D7 '    # BUFALO accepts NOVILLO
  [M12]='FAIL \[E6 '    # numero_fuego rejects instead of warning
  [M13]='FAIL \[D5 '    # no upper limit for the age
  [M14]='FAIL \[D1 '    # bovine ear tag not required
)
out=$($PSQL -f 099_tests.sql 2>&1); rc=$?
if [ $rc -eq 0 ] && grep -q 'assertions passed' <<<"$out"; then
  echo "M0 control: PASS ($(grep -oE '[0-9]+ assertions passed' <<<"$out"))"
else
  echo "M0 control: UNEXPECTED FAILURE"; echo "$out" | grep -E 'FAIL|ERROR' | head -3; fail=1
fi
for m in M1 M2 M3 M4 M5 M6 M7 M8 M9 M10 M11 M12 M13 M14; do
  out=$($PSQL -v mutation=$m -f 099_tests.sql 2>&1); rc=$?
  if [ $rc -ne 0 ] && grep -qE "${EXPECT[$m]}" <<<"$out"; then
    echo "$m: DETECTED -> $(grep -oE "FAIL \[[^]]*\]" <<<"$out" | head -1)"
  else
    echo "$m: NOT DETECTED (rc=$rc)"; echo "$out" | grep -E 'FAIL|ERROR' | head -3; fail=1
  fi
done
[ $fail -eq 0 ] && echo "MUTATION CHECK: OK (every mutation detected)" || echo "MUTATION CHECK: FAILED"
exit $fail
