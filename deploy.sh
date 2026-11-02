#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MAIN_COMPOSE="$SCRIPT_DIR/infrastructure/docker-compose.yml"
UPLOAD_COMPOSE="$SCRIPT_DIR/infrastructure/upload-file/docker-compose.yml"

cd "$SCRIPT_DIR"

skip_confirmation=false
if (($# > 0)) && [[ "$1" == "--yes" ]]; then
  skip_confirmation=true
  shift
fi

if (($# == 0)); then
  printf 'Usage: ./deploy.sh [--yes] <service> [<service>...]\n\n'
  printf 'Available infrastructure services:\n'
  docker compose -f "$MAIN_COMPOSE" config --services
  printf 'upload-file (separate compose file)\n'
  exit 1
fi

working_tree_clean=true
git diff --quiet || working_tree_clean=false
git diff --cached --quiet || working_tree_clean=false
if [[ "$working_tree_clean" != true ]]; then
  printf 'Refusing to deploy with tracked local modifications:\n' >&2
  if ! git diff --quiet; then
    printf 'Unstaged changes:\n' >&2
    git diff --name-only >&2
  fi
  if ! git diff --cached --quiet; then
    printf 'Staged changes:\n' >&2
    git diff --cached --name-only >&2
  fi
  exit 1
fi

contains_service() {
  local requested_service="$1"
  shift
  local available_service
  for available_service in "$@"; do
    if [[ "$requested_service" == "$available_service" ]]; then
      return 0
    fi
  done
  return 1
}

main_service_output="$(docker compose -f "$MAIN_COMPOSE" config --services)"
mapfile -t main_services <<< "$main_service_output"
upload_service_output=""
declare -a upload_services=()
declare -a validated_services=()
for requested_service in "$@"; do
  for previous_service in "${validated_services[@]}"; do
    if [[ "$requested_service" == "$previous_service" ]]; then
      printf 'Duplicate service requested: %s\n' "$requested_service" >&2
      exit 1
    fi
  done

  if [[ "$requested_service" == "upload-file" ]]; then
    if [[ -z "$upload_service_output" ]]; then
      upload_service_output="$(docker compose -f "$UPLOAD_COMPOSE" config --services)"
      mapfile -t upload_services <<< "$upload_service_output"
    fi
    if ! contains_service "$requested_service" "${upload_services[@]}"; then
      printf 'Service upload-file is not defined in %s\n' "$UPLOAD_COMPOSE" >&2
      exit 1
    fi
  else
    if ! contains_service "$requested_service" "${main_services[@]}"; then
      printf 'Unknown service: %s\nAvailable infrastructure services:\n%s\n' \
        "$requested_service" "$main_service_output" >&2
      printf 'upload-file (separate compose file)\n' >&2
      exit 1
    fi
  fi

  validated_services+=("$requested_service")
done

if [[ "$skip_confirmation" != true ]]; then
  printf 'Services to rebuild and recreate:\n'
  printf '  %s\n' "${validated_services[@]}"
  response=""
  if ! IFS= read -r -p "Type 'deploy' to continue: " response; then
    response=""
  fi
  if [[ "$response" != "deploy" ]]; then
    printf 'Deployment cancelled.\n' >&2
    exit 1
  fi
fi

git pull --ff-only origin main

timestamp="$(date '+%Y%m%d-%H%M')"
declare -a rollback_image_tags=()
declare -a rollback_image_refs=()
declare -a rollback_compose_files=()
declare -a rollback_services=()

print_rollback_commands() {
  local exit_status=$?
  trap - EXIT
  if ((${#rollback_services[@]} > 0)); then
    printf '\nRollback commands:\n'
    for index in "${!rollback_services[@]}"; do
      printf 'docker image tag %q %q\n' \
        "${rollback_image_tags[$index]}" "${rollback_image_refs[$index]}"
      printf 'docker compose -f %q up -d --no-build --no-deps --force-recreate %q\n' \
        "${rollback_compose_files[$index]}" "${rollback_services[$index]}"
    done
  fi
  exit "$exit_status"
}
trap print_rollback_commands EXIT

for service in "$@"; do
  compose_file="$MAIN_COMPOSE"
  if [[ "$service" == "upload-file" ]]; then
    compose_file="$UPLOAD_COMPOSE"
  fi

  container_ids="$(docker compose -f "$compose_file" ps --status running -q "$service")"
  if [[ -z "$container_ids" ]]; then
    printf 'No running container found for service %s; cannot create a rollback image.\n' \
      "$service" >&2
    exit 1
  fi
  mapfile -t running_containers <<< "$container_ids"

  container_id="${running_containers[0]}"
  running_image_id="$(docker inspect --format '{{.Image}}' "$container_id")"
  running_image_ref="$(docker inspect --format '{{.Config.Image}}' "$container_id")"
  for running_container in "${running_containers[@]:1}"; do
    other_image_id="$(docker inspect --format '{{.Image}}' "$running_container")"
    if [[ "$other_image_id" != "$running_image_id" ]]; then
      printf 'Running containers for %s use different images; refusing an ambiguous rollback.\n' \
        "$service" >&2
      exit 1
    fi
  done

  image_name="${running_image_ref%@*}"
  image_path="${image_name##*/}"
  if [[ "$image_path" == *:* ]]; then
    image_name="${image_name%:*}"
  fi
  rollback_tag="${image_name}:pre-deploy-${timestamp}"
  if docker image inspect "$rollback_tag" >/dev/null 2>&1; then
    printf 'Rollback tag already exists; refusing to overwrite it: %s\n' "$rollback_tag" >&2
    exit 1
  fi

  docker image tag "$running_image_id" "$rollback_tag"
  rollback_image_tags+=("$rollback_tag")
  rollback_image_refs+=("$running_image_ref")
  rollback_compose_files+=("$compose_file")
  rollback_services+=("$service")

  docker compose -f "$compose_file" build "$service"
  docker compose -f "$compose_file" up -d --no-build --no-deps --force-recreate "$service"

  printf '\nStatus for %s:\n' "$service"
  docker compose -f "$compose_file" ps "$service"
  printf '\nLast 10 log lines for %s:\n' "$service"
  docker compose -f "$compose_file" logs --tail=10 "$service"
done
