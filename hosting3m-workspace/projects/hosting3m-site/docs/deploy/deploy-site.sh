#!/usr/bin/env bash
# TEMPLATE. Versioned here, installed on the server BY HAND (root-owned, not writable by the subscription user).
# See README.md in this folder for the one-time setup. Never run code from the pulled branch: this script only
# reads the branch as data (SHA256SUMS, BUILD_INFO and the built files).
#
# Copies a built hosting3m-site artifact (branch deploy/prod, pulled by the hosting panel) into the
# docroot of the matching site. It never deletes anything from the docroot and never touches /webcard or /g.
#
# Usage: deploy-site.sh prod [--apply]
#   Without --apply it only verifies the artifact and prints what would change (dry run).
#   With --apply it backs up the docroot first, copies, and verifies the result.
#
# Runs as the subscription user (the one that owns the docroot), not as root.
set -euo pipefail

# All paths below are absolute. Leave the caller's working directory (a panel action may start the script from a
# directory this user cannot read, which makes find fail with "Failed to restore initial working directory").
cd /

# ---- Per-server settings: edit when installing ------------------------------------------------------
# Directory where the panel keeps the pulled artifact branch (a git working tree of deploy/prod).
# Keep the placeholders until the server paths are confirmed: the script refuses to run with them.
SRC_PROD="/CHANGE/ME/prod-artifact"
# Backups of the docroot. Set an ABSOLUTE path at install (it does not depend on HOME); it must be outside both docroots
# and is created with mode 700. --apply refuses while it still holds the placeholder or is not absolute.
# Old backups are never removed here.
BACKUP_ROOT="/CHANGE/ME/backups"
# ------------------------------------------------------------------------------------------------------

# Allowlisted docroots. Any other destination is refused.
readonly DOCROOT_PROD="/var/www/vhosts/hosting3m.com/httpdocs/"

usage() {
  echo "Usage: ${0##*/} prod [--apply]" >&2
  exit 2
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

target=""
apply=0
for arg in "$@"; do
  case "$arg" in
    prod)
      [[ -z "$target" ]] || usage
      target="$arg"
      ;;
    --apply) apply=1 ;;
    *) usage ;;
  esac
done
[[ -n "$target" ]] || usage

docroot="$DOCROOT_PROD"
src="$SRC_PROD"
expected_config="production"

# ---- Destination checks -----------------------------------------------------------------------------
[[ "$docroot" == "$DOCROOT_PROD" ]] || die "docroot is not allowlisted: $docroot"
[[ -d "$docroot" ]] || die "docroot does not exist: $docroot"
[[ ! -L "${docroot%/}" ]] || die "docroot is a symbolic link: $docroot"
[[ "$(realpath -e "$docroot")/" == "$docroot" ]] || die "docroot does not resolve to itself: $docroot"

# ---- Source checks ----------------------------------------------------------------------------------
[[ "$src" == /* ]] || die "artifact directory must be an absolute path: $src"
[[ "$src" != /CHANGE/ME/* ]] || die "SRC_PROD still holds the install placeholder: edit them first"
[[ -d "$src" ]] || die "artifact directory does not exist: $src"
[[ ! -L "${src%/}" ]] || die "artifact directory is a symbolic link: $src"
src="$(realpath -e "$src")"
# The artifact directory must be a separate staging area: never inside a docroot, never equal to one, never a parent of one.
case "$src/" in
  "$DOCROOT_PROD"*) die "artifact directory is inside or equal to a docroot: $src" ;;
esac
case "$DOCROOT_PROD" in
  "$src/"*) die "artifact directory contains a docroot: $src" ;;
esac
for required in SHA256SUMS BUILD_INFO index.html; do
  [[ -f "$src/$required" ]] || die "missing $required in the pulled artifact: $src"
done

config="$(sed -n 's/^config=//p' "$src/BUILD_INFO" | head -n 1)"
[[ "$config" == "$expected_config" ]] || die "BUILD_INFO config is '$config' but target '$target' needs '$expected_config'"
source_commit="$(sed -n 's/^source_commit=//p' "$src/BUILD_INFO" | head -n 1)"
built_at="$(sed -n 's/^built_at_utc=//p' "$src/BUILD_INFO" | head -n 1)"

# Manifest lines must look like "<64 hex>  <relative path>", with a safe path (no absolute path, no "..").
if grep -qvE '^[0-9a-f]{64}  [^[:space:]\\]([^\\]*[^[:space:]\\])?$' "$src/SHA256SUMS"; then
  die "SHA256SUMS has a malformed line"
fi
if awk '{ p = substr($0, 67) } p ~ /^\// || p ~ /(^|\/)\.\.(\/|$)/ { bad = 1 } END { exit !bad }' "$src/SHA256SUMS"; then
  die "SHA256SUMS lists an absolute path or a '..' component"
fi
if awk '{ p = substr($0, 67) } p ~ /^(webcard|g)(\/|$)/ { bad = 1 } END { exit !bad }' "$src/SHA256SUMS"; then
  die "SHA256SUMS lists a path under /webcard or /g: those Sitejet folders are never deployed"
fi
[[ -z "$(find "$src" -path "$src/.git" -prune -o -type l -print -quit)" ]] || die "the artifact contains a symbolic link"

# Verify BEFORE touching anything: every listed file matches, and nothing else is in the tree.
(cd "$src" && sha256sum --check --quiet SHA256SUMS) || die "checksum verification of the pulled artifact failed"
listed="$(awk '{ print substr($0, 67) }' "$src/SHA256SUMS" | LC_ALL=C sort)"
present="$(cd "$src" && find . -path ./.git -prune -o -type f ! -path ./SHA256SUMS -printf '%P\n' | LC_ALL=C sort)"
[[ "$listed" == "$present" ]] || die "files in the pulled artifact differ from SHA256SUMS (extra or missing files)"
manifest_index="$(awk '$2 == "index.html" { print $1 }' "$src/SHA256SUMS")"
[[ -n "$manifest_index" ]] || die "SHA256SUMS does not list index.html"

echo "Artifact verified: $(wc -l < "$src/SHA256SUMS") file(s), commit ${source_commit:0:12}, built ${built_at:-unknown}, config $config."
echo "Target: $target -> $docroot"

# Never copy git metadata; never touch the Sitejet asset folders. No --delete, ever.
# --checksum: decide by content, not by size and mtime (a changed file of the same size must still be copied).
rsync_args=(-a --checksum --no-owner --no-group --itemize-changes --exclude=/.git --exclude=/webcard --exclude=/g)

if ((apply == 0)); then
  echo "Dry run (nothing is written). Files that would be added or replaced:"
  rsync "${rsync_args[@]}" --dry-run "$src/" "$docroot"
  echo "Dry run finished. Re-run with --apply to back up the docroot and copy."
  exit 0
fi

# ---- Apply ------------------------------------------------------------------------------------------
[[ "$BACKUP_ROOT" != /CHANGE/ME/* ]] || die "BACKUP_ROOT still holds the install placeholder: set an absolute path first"
[[ "$BACKUP_ROOT" == /* ]] || die "BACKUP_ROOT must be an absolute path: $BACKUP_ROOT"
case "$(realpath -m "$BACKUP_ROOT")/" in
  "$DOCROOT_PROD"*) die "BACKUP_ROOT must be outside the docroot: $BACKUP_ROOT" ;;
esac
mkdir -p "$BACKUP_ROOT"
chmod 700 "$BACKUP_ROOT"

lock="$BACKUP_ROOT/.deploy.lock"
exec 9> "$lock"
flock -n 9 || die "another deployment is running (lock: $lock)"

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup="$BACKUP_ROOT/$target-$stamp.tar.gz"
[[ ! -e "$backup" ]] || die "backup already exists: $backup"

echo "Backing up $docroot -> $backup"
(umask 077 && tar -C "$docroot" -czf "$backup.partial" .) || die "backup failed; nothing was copied"
test -s "$backup.partial" || die "backup is empty; nothing was copied"
tar -tzf "$backup.partial" > /dev/null || die "backup is not readable; nothing was copied"
mv "$backup.partial" "$backup"
chmod 600 "$backup"
echo "Backup ready: $backup ($(wc -c < "$backup") bytes)"

rollback_cmd="tar -C '${docroot%/}' -xzf '$backup'"

echo "Copying..."
if ! rsync "${rsync_args[@]}" "$src/" "$docroot"; then
  echo "ERROR: the copy failed. To restore the previous files run: $rollback_cmd" >&2
  exit 1
fi

# Post-copy: index.html must equal the manifest, and so must every other listed file.
live_index="$(sha256sum "$docroot/index.html" | cut -d' ' -f1)"
if [[ "$live_index" != "$manifest_index" ]]; then
  echo "ERROR: index.html in the docroot does not match the manifest. To restore the previous files run: $rollback_cmd" >&2
  exit 1
fi
if ! (cd "$docroot" && sha256sum --check --quiet "$src/SHA256SUMS"); then
  echo "ERROR: files in the docroot do not match the manifest. To restore the previous files run: $rollback_cmd" >&2
  exit 1
fi

echo "Deployed commit ${source_commit:0:12} to $target. index.html sha256 $live_index matches the manifest."
echo
echo "Existing backups (never removed by this script; delete old ones by hand):"
find "$BACKUP_ROOT" -maxdepth 1 -name "$target-*.tar.gz" -printf '  %TY-%Tm-%Td %TH:%TM  %s bytes  %p\n' | LC_ALL=C sort
echo
echo "Rollback (extracts over the docroot, deletes nothing):"
echo "  $rollback_cmd"
echo "Next: purge the CDN for the changed unhashed URLs and run the smoke tests in the runbook."
