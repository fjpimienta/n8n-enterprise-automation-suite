#!/usr/bin/env bash
# Usage (VPS only, from the folder holding the 094/095 .sql files): ./run_m094.sh check <before|applied_094|applied_095> | dry 094|095 | apply 094|095 | rollback-dry | rollback-apply
set -euo pipefail
case "$(hostname)" in hosting3m*) ;; *) echo "NOT the VPS"; exit 1 ;; esac
cd "$(dirname "$0")"
p() { docker exec -i n8n-enterprise-db sh -c 'psql -U "$POSTGRES_USER" -d hosting3m_db -v ON_ERROR_STOP=1 "$@"' sh "$@"; }
case "${1:-}" in
  check)          p -v expect="$2" -f - < 094_state_check.sql ;;
  dry)            p -f - < "$( [ "$2" = 094 ] && echo 094_hotel_tickets_tenant.sql || echo 095_hotel_tickets_drop_default.sql )" ;;
  apply)          p -v apply=true -f - < "$( [ "$2" = 094 ] && echo 094_hotel_tickets_tenant.sql || echo 095_hotel_tickets_drop_default.sql )" ;;
  rollback-dry)   p -f - < 094_rollback.sql ;;
  rollback-apply) p -v apply=true -f - < 094_rollback.sql ;;
  *) echo "see header"; exit 2 ;;
esac
