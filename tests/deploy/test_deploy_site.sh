#!/usr/bin/env bash
# Tests for hosting3m-site/docs/deploy/deploy-site.sh and scripts/package-artifact.sh.
# The deploy script is copied into a temp tree with its allowlisted paths rewritten to temp directories, and
# rsync/tar are wrapped by stubs that log their arguments and can simulate failures (same pattern as test_deploy.sh).
set -u

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
site_dir="$repo_root/hosting3m-workspace/projects/hosting3m-site"
original_script="$site_dir/docs/deploy/deploy-site.sh"
package_script="$site_dir/scripts/package-artifact.sh"

temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

bin_dir="$temp_dir/bin"
log_file="$temp_dir/commands.log"
mkdir -p "$bin_dir"
: > "$log_file"

real_rsync="$(command -v rsync)"
real_tar="$(command -v tar)"
export REAL_RSYNC="$real_rsync" REAL_TAR="$real_tar" LOG_FILE="$log_file"

cat > "$bin_dir/rsync" <<'FAKE_RSYNC'
#!/usr/bin/env bash
printf 'rsync %s\n' "$*" >> "$LOG_FILE"
if [[ "${FAKE_RSYNC_NOOP:-0}" == "1" ]]; then
  exit 0
fi
exec "$REAL_RSYNC" "$@"
FAKE_RSYNC

cat > "$bin_dir/tar" <<'FAKE_TAR'
#!/usr/bin/env bash
printf 'tar %s\n' "$*" >> "$LOG_FILE"
if [[ "${FAKE_TAR_EMPTY:-0}" == "1" ]]; then
  while (($# > 0)); do
    if [[ "$1" == "-czf" ]]; then
      : > "$2"
      exit 0
    fi
    shift
  done
fi
exec "$REAL_TAR" "$@"
FAKE_TAR
chmod +x "$bin_dir/rsync" "$bin_dir/tar"
export PATH="$bin_dir:$PATH"

failures=0
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}
assert_exit() {
  [[ "$3" -eq "$2" ]] || fail "$1 (expected exit $2, got $3)"
}
assert_contains() {
  grep -Fq -- "$3" "$2" || fail "$1 (missing '$3')"
}
assert_not_contains() {
  ! grep -Fq -- "$3" "$2" || fail "$1 (unexpected '$3')"
}
assert_file() {
  [[ -f "$2" ]] || fail "$1 (missing file $2)"
}
assert_no_file() {
  [[ ! -e "$2" ]] || fail "$1 (unexpected path $2)"
}
assert_same_content() {
  [[ "$(cat "$2")" == "$3" ]] || fail "$1 ($2 holds '$(cat "$2")', expected '$3')"
}

# ---- Static checks on the versioned template -------------------------------------------------------
if grep -qi 'beta' "$original_script"; then fail "template has no beta target"; fi
assert_contains "template allowlists the prod docroot" "$original_script" 'readonly DOCROOT_PROD="/var/www/vhosts/hosting3m.com/httpdocs/"'
assert_contains "template excludes /webcard" "$original_script" '--exclude=/webcard'
assert_contains "template excludes /g" "$original_script" '--exclude=/g'
if grep -E '^[^#]*rsync[^#]*--delete' "$original_script" > /dev/null; then
  fail "template must never pass --delete to rsync"
fi
assert_contains "template ships install placeholders" "$original_script" '/CHANGE/ME/'

out="$temp_dir/stdout"
err="$temp_dir/stderr"
status=0
run() {
  local script="$1"
  shift
  if "$script" "$@" > "$out" 2> "$err"; then status=0; else status=$?; fi
}

# ---- Argument handling on the untouched template ---------------------------------------------------
: > "$log_file"
run "$original_script"
assert_exit "no arguments" 2 "$status"
run "$original_script" staging
assert_exit "unknown target" 2 "$status"
run "$original_script" /etc
assert_exit "a path is not a target" 2 "$status"
run "$original_script" beta
assert_exit "the removed beta target is refused" 2 "$status"
run "$original_script" prod prod
assert_exit "two targets" 2 "$status"
run "$original_script" prod --delete
assert_exit "unknown flag" 2 "$status"
assert_not_contains "bad arguments touch nothing" "$log_file" "rsync"
assert_not_contains "bad arguments make no backup" "$log_file" "tar"

# ---- Fixture helpers --------------------------------------------------------------------------------
fake_commit="0123456789abcdef0123456789abcdef01234567"

# make_env <name>: temp tree with a docroot, a source artifact (from the real packaging script) and a patched script copy.
make_env() {
  local name="$1" configuration="${2:-production}"
  env_root="$temp_dir/$name"
  mkdir -p "$env_root/dist/assets" "$env_root/httpdocs" "$env_root/home"
  if [[ -n "${EXTRA_DIST_DIR:-}" ]]; then
    mkdir -p "$env_root/dist/$EXTRA_DIST_DIR"
    printf 'x\n' > "$env_root/dist/$EXTRA_DIST_DIR/file.txt"
  fi
  printf '<html>new</html>\n' > "$env_root/dist/index.html"
  printf 'new asset\n' > "$env_root/dist/assets/app.js"
  # existing docroot: old site, legacy file, and the Sitejet asset folders
  printf '<html>old</html>\n' > "$env_root/httpdocs/index.html"
  printf 'legacy\n' > "$env_root/httpdocs/legacy.html"
  mkdir -p "$env_root/httpdocs/webcard" "$env_root/httpdocs/g"
  printf 'sitejet\n' > "$env_root/httpdocs/webcard/keep.txt"
  printf 'sitejet\n' > "$env_root/httpdocs/g/keep.txt"
  bash "$package_script" "$env_root/dist" "$env_root/src-prod" "$configuration" "$fake_commit" develop > /dev/null
  docroot="$env_root/httpdocs/"
  backups="$env_root/home/backups"
  script="$env_root/deploy-site.sh"
  sed -e "s#/var/www/vhosts/hosting3m.com/httpdocs/#$docroot#" \
      -e "s#^SRC_PROD=.*#SRC_PROD=\"$env_root/src-prod\"#" \
      -e "s#^BACKUP_ROOT=.*#BACKUP_ROOT=\"$backups\"#" \
      "$original_script" > "$script"
  chmod +x "$script"
  : > "$log_file"
}

# ---- Dry run (default) ------------------------------------------------------------------------------
make_env dryrun
run "$script" prod
assert_exit "dry run" 0 "$status"
assert_contains "dry run says it is a dry run" "$out" "Dry run"
assert_contains "dry run uses rsync --dry-run" "$log_file" "--dry-run"
assert_same_content "dry run leaves index.html alone" "${docroot}index.html" "<html>old</html>"
assert_no_file "dry run creates no backup directory" "$backups"
assert_no_file "dry run copies no new file" "${docroot}assets/app.js"

# ---- Apply ------------------------------------------------------------------------------------------
make_env apply
run "$script" prod --apply
assert_exit "apply" 0 "$status"
assert_same_content "apply copies the new index.html" "${docroot}index.html" "<html>new</html>"
assert_same_content "apply copies new files" "${docroot}assets/app.js" "new asset"
assert_file "apply keeps files that are not in the artifact" "${docroot}legacy.html"
assert_file "apply keeps /webcard" "${docroot}webcard/keep.txt"
assert_file "apply keeps /g" "${docroot}g/keep.txt"
assert_no_file "apply never copies git metadata" "${docroot}.git"
assert_contains "apply passes the /webcard exclude" "$log_file" "--exclude=/webcard"
assert_contains "apply passes the /g exclude" "$log_file" "--exclude=/g"
assert_not_contains "apply never passes --delete" "$log_file" "--delete"
assert_contains "apply prints the rollback command" "$out" "Rollback"
assert_contains "apply prints the extract command" "$out" "tar -C"
backup_file="$(find "$backups" -maxdepth 1 -name 'prod-*.tar.gz' | head -n 1)"
[[ -n "$backup_file" && -s "$backup_file" ]] || fail "apply writes a non-empty backup"
[[ "$(stat -c %a "$backups")" == "700" ]] || fail "backup directory has mode 700"
[[ "$(stat -c %a "$backup_file")" == "600" ]] || fail "backup file has mode 600"
if ! tar -tzf "$backup_file" | grep -q 'index.html'; then fail "backup holds the old index.html"; fi
if ! tar -tzf "$backup_file" | grep -q 'webcard/keep.txt'; then fail "backup holds /webcard too"; fi
assert_contains "old backups are listed" "$out" "Existing backups"
# the backup must be taken before the copy
backup_line="$(awk '/^tar .*-czf/ { print NR; exit }' "$log_file")"
copy_line="$(awk '/^rsync/ && !/--dry-run/ { print NR; exit }' "$log_file")"
if [[ -z "$backup_line" || -z "$copy_line" ]] || ((backup_line >= copy_line)); then
  fail "backup runs before the copy"
fi
# the rollback command really restores the old file
"$real_tar" -C "${docroot%/}" -xzf "$backup_file"
assert_same_content "rollback restores the old index.html" "${docroot}index.html" "<html>old</html>"

# a second run keeps the first backup (nothing is deleted)
sleep 1
run "$script" prod --apply
assert_exit "second apply" 0 "$status"
count="$(find "$backups" -maxdepth 1 -name 'prod-*.tar.gz' | wc -l)"
[[ "$count" -eq 2 ]] || fail "second apply keeps the first backup (found $count backups)"

# ---- Refusals: nothing may be touched ---------------------------------------------------------------
make_env wrong-config beta
run "$script" prod --apply
assert_exit "beta-configuration artifact on prod" 1 "$status"
assert_contains "wrong config explains itself" "$err" "BUILD_INFO config"
assert_same_content "wrong config leaves index.html alone" "${docroot}index.html" "<html>old</html>"
assert_no_file "wrong config makes no backup" "$backups"

make_env tampered
printf 'tampered\n' > "$env_root/src-prod/assets/app.js"
run "$script" prod --apply
assert_exit "tampered file" 1 "$status"
assert_contains "tampered file is reported" "$err" "checksum verification"
assert_same_content "tampered leaves index.html alone" "${docroot}index.html" "<html>old</html>"
assert_no_file "tampered makes no backup" "$backups"

make_env extra-file
printf 'extra\n' > "$env_root/src-prod/extra.html"
run "$script" prod
assert_exit "extra file (even on a dry run)" 1 "$status"
assert_contains "extra file is reported" "$err" "extra or missing"

make_env symlink
ln -s /etc/passwd "$env_root/src-prod/link.html"
run "$script" prod
assert_exit "symbolic link in the artifact" 1 "$status"
assert_contains "symlink is reported" "$err" "symbolic link"

EXTRA_DIST_DIR=g make_env sitejet-path
run "$script" prod --apply
assert_exit "artifact with a /g path" 1 "$status"
assert_contains "/g path is reported" "$err" "/webcard or /g"
assert_no_file "/g path makes no backup" "$backups"

make_env no-manifest
rm "$env_root/src-prod/SHA256SUMS"
run "$script" prod
assert_exit "missing SHA256SUMS" 1 "$status"

make_env placeholder
sed -i -e "s#^SRC_PROD=.*#SRC_PROD=\"/CHANGE/ME/prod-artifact\"#" "$script"
run "$script" prod
assert_exit "install placeholder" 1 "$status"
assert_contains "placeholder is reported" "$err" "install placeholder"

make_env backup-inside-docroot
sed -i -e "s#^BACKUP_ROOT=.*#BACKUP_ROOT=\"${docroot}backups\"#" "$script"
run "$script" prod --apply
assert_exit "backup directory inside the docroot" 1 "$status"
assert_same_content "backup-in-docroot leaves index.html alone" "${docroot}index.html" "<html>old</html>"

# ---- Artifact directory must be a separate staging area ---------------------------------------------
make_env src-under-docroot
mkdir -p "${docroot}staging"
cp -R "$env_root/src-prod/." "${docroot}staging/"
sed -i -e "s#^SRC_PROD=.*#SRC_PROD=\"${docroot}staging\"#" "$script"
run "$script" prod --apply
assert_exit "artifact directory under the docroot" 1 "$status"
assert_contains "src under docroot is reported" "$err" "inside or equal to a docroot"
assert_no_file "src under docroot makes no backup" "$backups"
assert_same_content "src under docroot leaves index.html alone" "${docroot}index.html" "<html>old</html>"

make_env src-equals-docroot
sed -i -e "s#^SRC_PROD=.*#SRC_PROD=\"${docroot%/}\"#" "$script"
run "$script" prod
assert_exit "artifact directory equal to a docroot" 1 "$status"
assert_contains "src equal to docroot is reported" "$err" "inside or equal to a docroot"

make_env src-contains-docroot
sed -i -e "s#^SRC_PROD=.*#SRC_PROD=\"$env_root\"#" "$script"
run "$script" prod
assert_exit "artifact directory that contains a docroot" 1 "$status"
assert_contains "src containing a docroot is reported" "$err" "contains a docroot"

# ---- BACKUP_ROOT is set at install, absolute ---------------------------------------------------------
assert_contains "template ships the BACKUP_ROOT placeholder" "$original_script" 'BACKUP_ROOT="/CHANGE/ME/backups"'
make_env backup-placeholder
sed -i -e "s#^BACKUP_ROOT=.*#BACKUP_ROOT=\"/CHANGE/ME/backups\"#" "$script"
run "$script" prod --apply
assert_exit "BACKUP_ROOT placeholder" 1 "$status"
assert_contains "BACKUP_ROOT placeholder is reported" "$err" "install placeholder"
assert_same_content "BACKUP_ROOT placeholder leaves index.html alone" "${docroot}index.html" "<html>old</html>"
run "$script" prod
assert_exit "dry run does not need BACKUP_ROOT" 0 "$status"

make_env backup-relative
sed -i -e "s#^BACKUP_ROOT=.*#BACKUP_ROOT=\"relative/backups\"#" "$script"
HOME="$env_root/home" run "$script" prod --apply
assert_exit "relative BACKUP_ROOT" 1 "$status"
assert_contains "relative BACKUP_ROOT is reported" "$err" "absolute path"
assert_no_file "relative BACKUP_ROOT writes nothing under HOME" "$env_root/home/relative"
assert_same_content "relative BACKUP_ROOT leaves index.html alone" "${docroot}index.html" "<html>old</html>"

make_env wrong-docroot
sed -i -e "s#^readonly DOCROOT_PROD=.*#readonly DOCROOT_PROD=\"$env_root/nope/\"#" "$script"
run "$script" prod
assert_exit "missing docroot" 1 "$status"

# ---- Started from a working directory that no longer exists (regression guard; the noise itself was not reproducible locally)
make_env gone-cwd
mkdir "$env_root/gone"
(cd "$env_root/gone" && rmdir "$env_root/gone" && "$script" prod > "$out" 2> "$err")
status=$?
assert_exit "dry run from a removed working directory" 0 "$status"
assert_not_contains "no working-directory noise" "$err" "initial working directory"

# ---- Failure handling during apply ------------------------------------------------------------------
make_env empty-backup
FAKE_TAR_EMPTY=1 run "$script" prod --apply
assert_exit "empty backup" 1 "$status"
assert_contains "empty backup is reported" "$err" "backup is empty"
assert_same_content "empty backup leaves index.html alone" "${docroot}index.html" "<html>old</html>"
if grep '^rsync' "$log_file" | grep -qv -- '--dry-run'; then fail "empty backup never runs the copy"; fi

make_env copy-did-nothing
FAKE_RSYNC_NOOP=1 run "$script" prod --apply
assert_exit "copy that changed nothing" 1 "$status"
assert_contains "post-copy check catches it" "$err" "does not match the manifest"
assert_contains "post-copy failure prints the rollback" "$err" "tar -C"

if ((failures > 0)); then
  printf '%s assertion(s) failed.\n' "$failures" >&2
  exit 1
fi

printf 'All deploy-site.sh checks passed.\n'
