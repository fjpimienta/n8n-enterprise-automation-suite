#!/usr/bin/env bash
set -u

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

test_root="$temp_dir/repo"
bin_dir="$temp_dir/bin"
log_file="$temp_dir/commands.log"
mkdir -p "$test_root/infrastructure/upload-file" "$bin_dir"
cp "$repo_root/deploy.sh" "$test_root/deploy.sh"
: > "$test_root/infrastructure/docker-compose.yml"
: > "$test_root/infrastructure/upload-file/docker-compose.yml"
: > "$log_file"

cat > "$bin_dir/docker" <<'FAKE_DOCKER'
#!/usr/bin/env bash
printf 'docker %s\n' "$*" >> "$LOG_FILE"

case "$*" in
  "compose "*" config --services")
    printf 'jwt-service\nn8n\n'
    if [[ "$*" == *upload-file* ]]; then
      printf 'upload-file\n'
    fi
    ;;
  "compose "*" ps --status running -q "*)
    service="${@: -1}"
    printf 'cid-%s\n' "$service"
    ;;
  "inspect --format {{.Image}} "*)
    printf 'sha256:img1234\n'
    ;;
  "inspect --format {{.Config.Image}} "*)
    if [[ "${@: -1}" == "cid-n8n" ]]; then
      printf 'n8nio/n8n:2.23.3\n'
    else
      printf 'infrastructure-jwt-service\n'
    fi
    ;;
  "image inspect "*)
    exit 1
    ;;
esac
FAKE_DOCKER

cat > "$bin_dir/git" <<'FAKE_GIT'
#!/usr/bin/env bash
printf 'git %s\n' "$*" >> "$LOG_FILE"

if [[ "$1" == "diff" && "$2" == "--quiet" && "${DIRTY:-0}" == "1" ]]; then
  exit 1
fi

exit 0
FAKE_GIT

chmod +x "$bin_dir/docker" "$bin_dir/git"
export PATH="$bin_dir:$PATH"
export LOG_FILE="$log_file"

failures=0

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}

assert_exit() {
  local name="$1"
  local expected="$2"
  local actual="$3"
  if [[ "$actual" -ne "$expected" ]]; then
    fail "$name (expected exit $expected, got $actual)"
  fi
}

assert_contains() {
  local name="$1"
  local file="$2"
  local expected="$3"
  if ! grep -Fq -- "$expected" "$file"; then
    fail "$name (missing '$expected')"
  fi
}

assert_not_contains() {
  local name="$1"
  local file="$2"
  local unexpected="$3"
  if grep -Fq -- "$unexpected" "$file"; then
    fail "$name (unexpected '$unexpected')"
  fi
}

assert_order() {
  local name="$1"
  local first="$2"
  local second="$3"
  local third="$4"
  local fourth="$5"
  local first_line second_line third_line fourth_line
  first_line="$(awk -v needle="$first" 'index($0, needle) { print NR; exit }' "$log_file")"
  second_line="$(awk -v needle="$second" 'index($0, needle) { print NR; exit }' "$log_file")"
  third_line="$(awk -v needle="$third" 'index($0, needle) { print NR; exit }' "$log_file")"
  fourth_line="$(awk -v needle="$fourth" 'index($0, needle) { print NR; exit }' "$log_file")"

  if [[ -z "$first_line" || -z "$second_line" || -z "$third_line" || -z "$fourth_line" ]]; then
    fail "$name (one or more ordered commands are missing)"
  elif ((first_line >= second_line || second_line >= third_line || third_line >= fourth_line)); then
    fail "$name (commands were not in the expected order)"
  fi
}

clear_log() {
  : > "$log_file"
  unset DIRTY
}

run_deploy() {
  local output_file="$1"
  local error_file="$2"
  shift 2
  if "$test_root/deploy.sh" "$@" > "$output_file" 2> "$error_file"; then
    command_status=0
  else
    command_status=$?
  fi
}

output_file="$temp_dir/stdout"
error_file="$temp_dir/stderr"

clear_log
run_deploy "$output_file" "$error_file"
assert_exit "no arguments" 1 "$command_status"
assert_contains "no arguments usage" "$output_file" "Usage"

clear_log
run_deploy "$output_file" "$error_file" unknown-service
assert_exit "unknown service" 1 "$command_status"
assert_not_contains "unknown service does not pull" "$log_file" "git pull"
assert_not_contains "unknown service does not tag an image" "$log_file" "image tag"

clear_log
run_deploy "$output_file" "$error_file" jwt-service jwt-service
assert_exit "duplicate service" 1 "$command_status"

clear_log
DIRTY=1 run_deploy "$output_file" "$error_file" jwt-service
assert_exit "dirty working tree" 1 "$command_status"
assert_not_contains "dirty working tree does not pull" "$log_file" "git pull"

clear_log
if printf 'no\n' | "$test_root/deploy.sh" jwt-service > "$output_file" 2> "$error_file"; then
  command_status=0
else
  command_status=$?
fi
assert_exit "confirmation declined" 1 "$command_status"
assert_not_contains "declined deployment does not pull" "$log_file" "git pull"
assert_not_contains "declined deployment does not tag an image" "$log_file" "image tag"

clear_log
run_deploy "$output_file" "$error_file" --yes jwt-service
assert_exit "jwt-service deploy" 0 "$command_status"
assert_order "jwt-service deployment command order" \
  "git pull --ff-only" \
  "docker image tag sha256:img1234 infrastructure-jwt-service:pre-deploy-" \
  " build jwt-service" \
  " up -d --no-build --no-deps --force-recreate jwt-service"

clear_log
if printf 'deploy\n' | "$test_root/deploy.sh" n8n > "$output_file" 2> "$error_file"; then
  command_status=0
else
  command_status=$?
fi
assert_exit "n8n deploy" 0 "$command_status"
if ! grep -Eq '^docker image tag [^ ]+ n8nio/n8n:2\.23\.3$' "$output_file"; then
  fail "n8n rollback retags exactly to n8nio/n8n:2.23.3"
fi
assert_not_contains "n8n rollback does not use latest" "$output_file" "n8nio/n8n:latest"

if ((failures > 0)); then
  printf '%s assertion(s) failed.\n' "$failures" >&2
  exit 1
fi

printf 'All deploy.sh checks passed.\n'
