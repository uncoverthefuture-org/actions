#!/usr/bin/env bash
# Managed recreate and blue-green releases. Source from podman.sh or invoke with rollback <root> <tag|previous>.
# Release records contain secrets and must stay private to the deployment user.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/blue-green.sh"

release_error() { echo "::error::$*" >&2; return 1; }
release_valid_id() { [[ "$1" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]{0,95}$ ]]; }

release_lock() {
  umask 077
  mkdir -p "$1/releases" || return
  chmod 700 "$1" "$1/releases" || return
  mkdir "$1/.lock" 2>/dev/null || { release_error "Another release operation holds $1/.lock; investigate stale locks before removing them"; return 1; }
  printf '%s\n' "$$" > "$1/.lock/pid"
}

release_check() {
  local dir="$1"
  [[ -d "$dir" && ! -L "$dir" ]] || { release_error 'Release directory is missing or is a symlink'; return 1; }
  (cd "$dir" && sha256sum --check --status checksums) || { release_error 'Release snapshot failed integrity verification'; return 1; }
  jq -e '.schema == 1 and (.argv | type == "array") and .argv[0] == "podman" and .argv[1] == "run"' "$dir/release.json" >/dev/null
}

release_read_argv() {
  RELEASE_ARGV=()
  local arg
  while IFS= read -r -d '' arg; do RELEASE_ARGV+=("$arg"); done < <(jq -j '.argv[] | ., "\u0000"' "$1/release.json")
  ((${#RELEASE_ARGV[@]} > 3))
}

release_wait() {
  local container="$1" state attempt
  for ((attempt=0; attempt<60; attempt++)); do
    state=$(podman inspect --format '{{json .State}}' "$container") || return
    case "$(printf '%s' "$state" | jq -r '.Status')" in exited|dead|removing) return 1;; esac
    if [[ "$(printf '%s' "$state" | jq -r '.Health.Status // .Healthcheck.Status // empty')" == healthy ]]; then return 0; fi
    sleep 2
  done
  release_error 'Container did not become healthy within 120 seconds'
}

release_service_stop() {
  local dir="$1" unit
  [[ -f "$dir/service.name" ]] || return 0
  unit=$(cat "$dir/service.name")
  [[ -f "$HOME/.config/systemd/user/$unit" ]] || return 0
  if command -v systemctl >/dev/null; then
    systemctl --user stop "$unit" >/dev/null 2>&1 || return 1
    systemctl --user disable "$unit" >/dev/null 2>&1 || return 1
  fi
}

release_start() {
  local dir="$1" name
  release_check "$dir" || return
  podman load --input "$dir/image.tar" >/dev/null || return
  release_read_argv "$dir" || return
  release_service_stop "$dir" || return
  name=$(jq -r '.container' "$dir/release.json")
  if podman container exists "$name" >/dev/null 2>&1; then podman rm --force "$name" >/dev/null || return; fi
  "${RELEASE_ARGV[@]}" >/dev/null || return
  release_wait "$name"
}

release_persist() {
  local dir="$1" unit unit_dir escaped_path name
  [[ "$(jq -r '.persist' "$dir/release.json")" == true ]] || return 0
  command -v systemctl >/dev/null || { release_error 'Managed persistence requires systemd --user; disable quadlet_enabled explicitly for ephemeral deployments'; return 1; }
  name=$(jq -r '.container' "$dir/release.json")
  unit="uactions-$(jq -r '.id' "$dir/release.json").service"
  unit_dir="$HOME/.config/systemd/user"
  mkdir -p "$unit_dir" || return
  # Percent is expanded by systemd even in quoted arguments.
  escaped_path=${dir//%/%%}; escaped_path=${escaped_path//\\/\\\\}; escaped_path=${escaped_path//\"/\\\"}
  cat > "$unit_dir/$unit" <<UNIT
[Unit]
Description=UActions immutable release
After=network-online.target
[Service]
Type=simple
ExecStart=/bin/bash "$escaped_path/start.sh"
ExecStop=-podman stop --time 30 $name
Restart=on-failure
RestartSec=3
[Install]
WantedBy=default.target
UNIT
  chmod 600 "$unit_dir/$unit" || return
  systemctl --user daemon-reload || return
  systemctl --user enable "$unit" >/dev/null || return
}

release_commit() {
  local root="$1" id="$2" previous="$3" tmp="$1/state.json.tmp" history='[]' tag host_port
  host_port=$(jq -r '.host_port // empty' "$root/releases/$id/release.json") || return
  tag=$(jq -er '.tag' "$root/releases/$id/release.json") || return
  if [[ -f "$root/state.json" ]]; then
    history=$(jq -ce '.activations // []' "$root/state.json") || return
  fi
  # Only successful activations enter this index. Newest entries come first;
  # redeploying a tag with different settings never loses the earlier snapshot.
  jq -n --arg current "$id" --arg previous "$previous" --arg tag "$tag" --argjson history "$history" --arg host_port "$host_port" \
    '{schema:1,current:$current,host_port:$host_port,previous:(if $previous == "" then null else $previous end),activated_at:now,activations:([{id:$current,tag:$tag}] + $history)}' > "$tmp" || return
  chmod 600 "$tmp" && mv "$tmp" "$root/state.json"
}

release_snapshot() {
  local root="$1" env_file="$2"; shift 2
  local -a args=("$@")
  local id dir image image_id health name='' i old_env="$env_file" arg persist=false strategy="${DEPLOYMENT_STRATEGY:-recreate}" routing='null' host_port='' mapping
  [[ -f "$env_file" ]] || { release_error 'Managed releases require an environment file'; return 1; }
  id="$(date -u +%Y%m%dT%H%M%SZ)-$(openssl rand -hex 6)"
  dir="$root/releases/$id"
  mkdir "$dir" || return
  image="${args[${#args[@]}-1]}"
  image_id=$(podman image inspect --format '{{.Id}}' "$image") || return
  [[ "$image_id" =~ ^sha256:[a-f0-9]{64}$ ]] || { release_error 'Image inspection did not return an immutable image ID'; return 1; }
  health=$(podman image inspect --format '{{json .Config.Healthcheck}}' "$image_id") || return
  printf '%s' "$health" | jq -e '.Test | type == "array" and length > 0 and .[0] != "NONE"' >/dev/null || { release_error 'Managed releases require an image-defined HEALTHCHECK before replacing traffic'; return 1; }
  cp "$env_file" "$dir/.env" || return
  # Preserve all resolved launch arguments, redirecting only the captured env file.
  for ((i=0; i<${#args[@]}; i++)); do
    arg="${args[$i]}"
    if [[ "$arg" == --name ]]; then name="${args[$((i+1))]}"; fi
    if [[ "$arg" == -p && -z "$host_port" ]]; then
      mapping="${args[$((i+1))]}"
      if [[ "$mapping" =~ ^([0-9]+):[0-9]+(/tcp)?$ ]]; then host_port="${BASH_REMATCH[1]}"; fi
    fi
    if [[ "$arg" == --env-file && "${args[$((i+1))]}" == "$old_env" ]]; then args[$((i+1))]="$dir/.env"; fi
    if [[ "$arg" == "$old_env":* ]]; then args[$i]="$dir/.env${arg#"$old_env"}"; fi
  done
  release_valid_id "$name" || { release_error 'Managed container name must be a simple identifier of at most 96 characters'; return 1; }
  case "$strategy" in
    recreate) ;;
    blue-green)
      bluegreen_prepare "$root" "$id" "$name" "${args[@]}" || return
      args=("${BG_ARGV[@]}"); name="$BG_NAME"; routing="$BG_ROUTING"
      printf '%s\n' "$BG_ROUTE" > "$dir/route.json" || return
      ;;
    *) release_error 'Unsupported deployment strategy'; return 1;;
  esac
  args[${#args[@]}-1]="$image_id"
  # Never fetch a mutable tag during a replay or reboot.
  args=("${args[@]:0:${#args[@]}-1}" --pull=never "$image_id")
  if [[ "${QUADLET_ENABLED:-true}" == true ]]; then
    command -v systemctl >/dev/null && systemctl --user show-environment >/dev/null 2>&1 || {
      release_error 'Managed persistence requires an available systemd user manager; disable quadlet_enabled for ephemeral deployments'
      return 1
    }
    persist=true
  fi
  printf '%s\0' "${args[@]}" | jq -Rs --arg id "$id" --arg name "$name" --arg image "$image_id" --arg reference "$image" --arg tag "${image##*:}" --arg strategy "$strategy" --argjson routing "$routing" --argjson persist "$persist" --arg host_port "$host_port" \
    '{schema:1,id:$id,host_port:$host_port,strategy:$strategy,routing:$routing,container:$name,image:$image,requested_image:$reference,tag:$tag,persist:$persist,argv:(split("\u0000")[:-1])}' > "$dir/release.json" || return
  podman save --format oci-archive --output "$dir/image.tar" "$image_id" >/dev/null || return
  # A faithful foreground replay for systemd; no reconstruction of runtime flags.
  {
    printf '#!/usr/bin/env bash\nset -euo pipefail\n'
    printf 'podman rm --force --ignore %q >/dev/null\n' "$name"
    printf 'podman load --input %q >/dev/null\n' "$dir/image.tar"
    printf 'exec '
    for ((i=0; i<${#args[@]}; i++)); do [[ "$i" == 2 && "${args[$i]}" == -d ]] || printf '%q ' "${args[$i]}"; done
    printf '\n'
  } > "$dir/start.sh"
  if [[ "$persist" == true ]]; then printf 'uactions-%s.service\n' "$id" > "$dir/service.name"; fi
  (cd "$dir" && sha256sum .env release.json image.tar start.sh > checksums && { [[ ! -f route.json ]] || sha256sum route.json >> checksums; } && { [[ ! -f service.name ]] || sha256sum service.name >> checksums; }) || return
  chmod 400 "$dir"/* "$dir/.env" || return
  chmod 500 "$dir" || return
  RELEASE_SNAPSHOT_DIR="$dir"
}

release_transition() {
  if [[ "$(jq -r '.strategy // "recreate"' "$1/releases/$2/release.json")" == blue-green ]]; then
    bluegreen_transition "$1" "$2"
    return $?
  fi
  local root="$1" target="$2" current='' old_dir='' old_name='' target_name
  release_check "$root/releases/$target" || return
  # Load/validate before stopping the active application.
  podman load --input "$root/releases/$target/image.tar" >/dev/null || return
  if [[ -f "$root/state.json" ]]; then
    current=$(jq -er '.current' "$root/state.json") || return
    release_valid_id "$current" || return 1
    [[ "$current" != "$target" ]] || return 0
    old_dir="$root/releases/$current"
    release_check "$old_dir" || return
    [[ "$(jq -r '.strategy // "recreate"' "$old_dir/release.json")" == recreate ]] || {
      release_error 'Switching deployment strategies requires an explicit migration'; return 1;
    }
    old_name=$(jq -r '.container' "$old_dir/release.json")
    release_service_stop "$old_dir" || return
    podman stop --time 30 "$old_name" >/dev/null || return
  fi
  target_name=$(jq -r '.container' "$root/releases/$target/release.json")
  if [[ -z "$current" ]] && podman container exists "$target_name" >/dev/null 2>&1; then
    release_error 'Existing unmanaged container found. Migrate it explicitly before enabling managed releases.'
    return 1
  fi
  if release_start "$root/releases/$target" && release_persist "$root/releases/$target" && release_commit "$root" "$target" "$current"; then
    if [[ -n "$old_name" && "$old_name" != "$target_name" ]]; then podman rm "$old_name" >/dev/null || true; fi
    printf 'Active release: %s\n' "$target"
    return 0
  fi
  release_service_stop "$root/releases/$target" || true
  podman rm --force "$target_name" >/dev/null 2>&1 || true
  if [[ -n "$old_dir" ]]; then
    if release_start "$old_dir" && release_persist "$old_dir"; then
      echo 'Previous release restored after deployment failure' >&2
    else
      release_error 'Deployment and recovery both failed; active state was not changed'
    fi
  fi
  return 1
}

release_deploy() (
  set -euo pipefail
  set +x
  local root="$1" env_file="$2"; shift 2
  release_lock "$root" || exit 1
  trap 'rm -rf "$root/.lock"' EXIT
  release_snapshot "$root" "$env_file" "$@" || exit 1
  release_transition "$root" "$(basename "$RELEASE_SNAPSHOT_DIR")"
)

release_rollback() (
  set -euo pipefail
  set +x
  local root="$1" target="$2"
  release_lock "$root" || exit 1
  trap 'rm -rf "$root/.lock"' EXIT
  if [[ "$target" == previous ]]; then
    target=$(jq -er '.previous // empty' "$root/state.json") || exit 1
  else
    [[ "$target" =~ ^[a-zA-Z0-9_][a-zA-Z0-9._-]{0,127}$ ]] || { release_error 'Invalid rollback image tag'; exit 1; }
    target=$(jq -er --arg tag "$target" '[.activations[]? | select(.tag == $tag)][0].id // empty' "$root/state.json") || {
      release_error 'No successfully activated snapshot exists for that image tag'
      exit 1
    }
  fi
  release_valid_id "$target" || { release_error 'Invalid saved release reference'; exit 1; }
  release_transition "$root" "$target"
)

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
  [[ "${1:-}" == rollback && $# == 3 ]] || { echo 'Usage: release-manager.sh rollback <release-root> <tag|previous>' >&2; exit 2; }
  release_rollback "$2" "$3"
fi
