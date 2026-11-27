#!/usr/bin/env bash
# Packages the built site into a deploy artifact: the built files at the root, BUILD_INFO and SHA256SUMS.
# Used by .github/workflows/hosting3m-site-artifact.yml; it can also be run locally to inspect an artifact.
#
# Usage: package-artifact.sh <built-dir> <out-dir> <configuration> <source-commit> <source-ref> [<plans-snapshot-file>]
#   <configuration>  beta | production
#   <out-dir>        must not exist or must be empty; it receives the artifact (no secrets, no source files)
#
# SHA256SUMS lists every file of the artifact except itself, sorted bytewise: "<sha256>  <relative path>".
set -euo pipefail

if (($# < 5 || $# > 6)); then
  echo "Usage: $0 <built-dir> <out-dir> <beta|production> <source-commit> <source-ref> [<plans-snapshot-file>]" >&2
  exit 2
fi

built_dir="$1"
out_dir="$2"
configuration="$3"
source_commit="$4"
source_ref="$5"
plans_file="${6:-}"

case "$configuration" in
  beta | production) ;;
  *)
    echo "Configuration must be beta or production, got '$configuration'." >&2
    exit 2
    ;;
esac
if [[ ! "$source_commit" =~ ^[0-9a-f]{40}$ ]]; then
  echo "Source commit must be a full 40-character lowercase hex SHA." >&2
  exit 2
fi
if [[ ! "$source_ref" =~ ^[A-Za-z0-9._/-]+$ ]]; then
  echo "Source ref contains unexpected characters." >&2
  exit 2
fi
if [[ ! -f "$built_dir/index.html" ]]; then
  echo "No index.html in '$built_dir': run the site build first." >&2
  exit 1
fi
if [[ -e "$out_dir" ]] && [[ -n "$(ls -A "$out_dir")" ]]; then
  echo "Output directory '$out_dir' is not empty." >&2
  exit 1
fi
if find "$built_dir" -type l | grep -q .; then
  echo "The build output contains symbolic links; refusing to package it." >&2
  exit 1
fi
# Names are parsed by column in SHA256SUMS: reject anything sha256sum would escape or a shell could mangle.
if find "$built_dir" -name '*\\*' -o -name '*
*' | grep -q .; then
  echo "The build output contains a file name with a backslash or a newline; refusing to package it." >&2
  exit 1
fi

mkdir -p "$out_dir"
cp -R "$built_dir"/. "$out_dir"/

{
  printf 'source_commit=%s\n' "$source_commit"
  printf 'source_ref=%s\n' "$source_ref"
  printf 'config=%s\n' "$configuration"
  printf 'built_at_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if [[ -n "$plans_file" ]]; then
    printf 'plans_snapshot_sha256=%s\n' "$(sha256sum "$plans_file" | cut -d' ' -f1)"
  fi
} > "$out_dir/BUILD_INFO"

(
  cd "$out_dir"
  find . -type f ! -path ./SHA256SUMS -printf '%P\0' | LC_ALL=C sort -z | xargs -0 sha256sum > SHA256SUMS
)

count="$(wc -l < "$out_dir/SHA256SUMS")"
echo "Artifact ready in $out_dir: $count file(s) listed in SHA256SUMS (config=$configuration, commit=${source_commit:0:12})."
