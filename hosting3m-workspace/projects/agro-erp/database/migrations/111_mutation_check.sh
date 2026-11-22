#!/usr/bin/env bash
# 111_mutation_check.sh: proves that the 111 tests notice the loss of each protection.
# M0 is the control (no mutation: all assertions pass). M1..M6 break one thing inside the test transaction (always rolled back):
#   M1 SALE branch of the role gate removed          M2 fail-closed (ROLE_UNAVAILABLE) branch removed
#   M3 test-company SAT skip applies to every company  M4 plantation left out of the preview hash
#   M5 voiding the expense no longer voids the link    M6 EDITOR allowed to register
# LOCAL / throw-away database only. Connection: standard libpq settings (PGHOST, PGPORT, PGUSER, PGDATABASE, ~/.pgpass), or PSQL="docker exec -i -w /tmp/m111 ... psql ..."
# (with the 109_* and 111_* files copied to that directory).
set -u
cd "$(dirname "$0")"
PSQL="${PSQL:-psql} -X -v ON_ERROR_STOP=1"
fail=0
out=$($PSQL -v mutation=none -f 111_tests.sql 2>&1); rc=$?
if [ $rc -eq 0 ] && grep -q 'assertions passed' <<<"$out"; then echo "M0 control: PASS ($(grep -o '[0-9]* assertions passed' <<<"$out"))"; else echo "M0 control: UNEXPECTED FAILURE"; echo "$out" | tail -5; exit 1; fi
for m in M1 M2 M3 M4 M5 M6; do
  out=$($PSQL -v mutation=$m -f 111_tests.sql 2>&1); rc=$?
  if [ $rc -ne 0 ] && grep -qE 'FAIL \[' <<<"$out"; then
    echo "$m: DETECTED -> $(grep -oE 'FAIL \[[^]]*\]' <<<"$out" | head -1)"
  else
    echo "$m: NOT DETECTED (rc=$rc)"; fail=1
  fi
done
exit $fail
