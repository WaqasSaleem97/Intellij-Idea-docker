#!/usr/bin/env bash
# Apply a light budget by default, or the optional 90% performance budget.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

fail() {
    printf 'Resource update stopped: %s\n' "$*" >&2
    exit 1
}

profile=light
configure_only=false
profile_selected=false
for option in "$@"; do
    case "$option" in
        --light|--performance)
            [[ "$profile_selected" == false ]] || fail 'Choose only one resource profile.'
            profile="${option#--}"
            profile_selected=true ;;
        --configure-only) configure_only=true ;;
        *) fail 'Usage: bash resources.sh [--light|--performance] [--configure-only]' ;;
    esac
done
[[ -f .env ]] || fail 'Run bash setup.sh first to create .env.'

docker compose version >/dev/null
host_resources="$(docker info --format '{{.NCPU}} {{.MemTotal}} {{.OSType}}')"
read -r host_cpus host_memory host_os <<< "$host_resources"
[[ "$host_os" == linux ]] || fail 'A Linux Docker host is required.'
[[ "$host_cpus" =~ ^[1-9][0-9]*$ && "$host_memory" =~ ^[1-9][0-9]*$ ]] \
    || fail 'Docker did not report usable CPU and RAM totals.'

cpu_hundredths=$((host_cpus * 90))
if [[ "$profile" == light ]]; then
    (( cpu_hundredths <= 200 )) || cpu_hundredths=200
    memory_mib=$((host_memory / 1024 / 1024 * 75 / 100))
    (( memory_mib <= 4096 )) || memory_mib=4096
    (( memory_mib >= 2048 )) || fail 'The light profile needs at least 2 GiB for the container; give the Docker host more RAM.'
else
    memory_mib=$((host_memory / 1024 / 1024 * 90 / 100))
    (( memory_mib >= 6 )) || fail 'Calculated RAM limit is below Docker minimum.'
fi
printf -v cpu_limit '%d.%02d' "$((cpu_hundredths / 100))" "$((cpu_hundredths % 100))"
memory_limit="${memory_mib}m"

# Never source .env. Replace only managed resource entries and preserve logins.
temporary="$(mktemp .env.resources.XXXXXX)"
trap 'rm -f -- "$temporary"' EXIT
awk '!/^[[:space:]]*(export[[:space:]]+)?IDEA_(CPU_LIMIT|MEMORY_LIMIT|MEMORY_SWAP_LIMIT|RESOURCE_PROFILE)[[:space:]]*=/' .env > "$temporary"
printf 'IDEA_CPU_LIMIT=%s\nIDEA_MEMORY_LIMIT=%s\nIDEA_MEMORY_SWAP_LIMIT=%s\nIDEA_RESOURCE_PROFILE=%s\n' \
    "$cpu_limit" "$memory_limit" "$memory_limit" "$profile" >> "$temporary"

export IDEA_CPU_LIMIT="$cpu_limit"
export IDEA_MEMORY_LIMIT="$memory_limit"
export IDEA_MEMORY_SWAP_LIMIT="$memory_limit"
compose=(docker compose --env-file "$temporary")
"${compose[@]}" config --quiet

printf '%s limits: %s CPU cores and %s MiB RAM; container swap disabled.\n' \
    "$profile" "$cpu_limit" "$memory_mib"
container_id=''
if [[ "$configure_only" != true ]]; then
    container_id="$("${compose[@]}" ps --all --quiet intellij)"
    if [[ -n "$container_id" ]]; then
        [[ "$container_id" != *$'\n'* ]] || fail 'Expected only one intellij container.'
        if ! docker update --cpus "$cpu_limit" --memory "$memory_limit" \
            --memory-swap "$memory_limit" "$container_id"; then
            fail 'Docker could not apply the limits. Your .env was not changed.'
        fi
    fi
fi

# mktemp keeps the credential-bearing file at mode 600.
mv -- "$temporary" .env || fail 'Could not save .env. Any successful live update remains active; rerun after fixing file permissions.'
printf 'Saved resource limits in .env for future container creation.\n'
if [[ -n "$container_id" ]]; then
    printf 'Updated the existing container without restarting or recreating it.\n'
elif [[ "$configure_only" != true ]]; then
    printf 'No existing intellij container found. Start it with: docker compose up -d\n'
fi
