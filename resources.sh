#!/usr/bin/env bash
# Run on the Docker host. Apply 90% CPU/RAM limits without recreating the container.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

fail() {
    printf 'Resource update stopped: %s\n' "$*" >&2
    exit 1
}

if (( $# > 1 )) || [[ "${1:-}" != '' && "${1:-}" != '--configure-only' ]]; then
    fail 'Usage: bash resources.sh [--configure-only]'
fi
[[ -f .env ]] || fail 'Run bash setup.sh first to create .env.'

docker compose version >/dev/null
# Query the Docker daemon, rather than assuming the client has the same hardware.
host_resources="$(docker info --format '{{.NCPU}} {{.MemTotal}} {{.OSType}}')"
read -r host_cpus host_memory host_os <<< "$host_resources"
[[ "$host_os" == linux ]] || fail 'A Linux Docker host is required.'
[[ "$host_cpus" =~ ^[1-9][0-9]*$ && "$host_memory" =~ ^[1-9][0-9]*$ ]] \
    || fail 'Docker did not report usable CPU and RAM totals.'

cpu_hundredths=$((host_cpus * 90))
printf -v cpu_limit '%d.%02d' "$((cpu_hundredths / 100))" "$((cpu_hundredths % 100))"
memory_mib=$((host_memory / 1024 / 1024 * 90 / 100))
(( memory_mib >= 6 )) || fail 'Calculated RAM limit is below Docker minimum.'
memory_limit="${memory_mib}m"

# Keep credentials and other settings; replace only the three resource keys.
# Never source .env as shell code or print its contents.
temporary="$(mktemp .env.resources.XXXXXX)"
trap 'rm -f -- "$temporary"' EXIT
awk '!/^[[:space:]]*(export[[:space:]]+)?IDEA_(CPU_LIMIT|MEMORY_LIMIT|MEMORY_SWAP_LIMIT)[[:space:]]*=/' .env > "$temporary"
printf 'IDEA_CPU_LIMIT=%s\nIDEA_MEMORY_LIMIT=%s\nIDEA_MEMORY_SWAP_LIMIT=%s\n' \
    "$cpu_limit" "$memory_limit" "$memory_limit" >> "$temporary"

# A RAM+swap limit equal to RAM disables container swap and keeps this budget
# in physical memory. Set both during live updates, including increases from 8g.
export IDEA_CPU_LIMIT="$cpu_limit"
export IDEA_MEMORY_LIMIT="$memory_limit"
export IDEA_MEMORY_SWAP_LIMIT="$memory_limit"
compose=(docker compose --env-file "$temporary")
"${compose[@]}" config --quiet

printf '90%% limits: %s CPU cores and %s MiB RAM; container swap disabled.\n' \
    "$cpu_limit" "$memory_mib"
container_id=''
if [[ "${1:-}" != '--configure-only' ]]; then
    container_id="$("${compose[@]}" ps --all --quiet intellij)"
    if [[ -n "$container_id" ]]; then
        [[ "$container_id" != *$'\n'* ]] || fail 'Expected only one intellij container.'
        if ! docker update --cpus "$cpu_limit" --memory "$memory_limit" \
            --memory-swap "$memory_limit" "$container_id"; then
            fail 'Docker could not apply the limits. Your .env was not changed.'
        fi
    fi
fi

# mktemp creates this file with mode 600, protecting the existing credentials.
if ! mv -- "$temporary" .env; then
    fail 'Could not save .env. Any successful live update remains active; rerun after fixing file permissions.'
fi
printf 'Saved resource limits in .env for future container creation.\n'
if [[ -n "$container_id" ]]; then
    printf 'Updated the existing container without restarting or recreating it.\n'
elif [[ "${1:-}" != '--configure-only' ]]; then
    printf 'No existing intellij container found. Start it with: docker compose up -d\n'
fi
