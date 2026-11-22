#!/usr/bin/env bash
# 109_mutation_check.sh: proves that the 109 tests notice the loss of each protection.
# M0 is the control (no mutation: all assertions pass). M1..M5 break one thing inside the test transaction (always rolled back):
#   M1 tax-id half of the own-RFC union removed   M2 issuer-RFC half removed   M3 company scope removed
#   M4 deactivated RFCs counted                   M5 issuer RFC not normalised
# LOCAL / throw-away database only. Connection: standard libpq settings (PGHOST, PGPORT, PGUSER, PGDATABASE, ~/.pgpass), or PSQL="docker exec ... psql ...".
set -u
cd "$(dirname "$0")"
PSQL="${PSQL:-psql} -X -v ON_ERROR_STOP=1"
fail=0
out=$($PSQL -v mutation=none -f 109_tests.sql 2>&1); rc=$?
if [ $rc -eq 0 ] && grep -q 'assertions passed' <<<"$out"; then echo "M0 control: PASS ($(grep -o '[0-9]* assertions passed' <<<"$out"))"; else echo "M0 control: UNEXPECTED FAILURE"; echo "$out" | tail -5; exit 1; fi
for m in M1 M2 M3 M4 M5; do
  out=$($PSQL -v mutation=$m -f 109_tests.sql 2>&1); rc=$?
  if [ $rc -ne 0 ] && grep -qE 'FAIL \[' <<<"$out"; then
    echo "$m: DETECTED -> $(grep -oE 'FAIL \[[^]]*\]' <<<"$out" | head -1)"
  else
    echo "$m: NOT DETECTED (rc=$rc)"; fail=1
  fi
done
exit $fail
