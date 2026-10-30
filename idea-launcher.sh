#!/usr/bin/env bash
set -euo pipefail

idea_install_dir="${IDEA_INSTALL_DIR:-/opt/idea}"

# Keep the vendor/user VM options by default. Generate a heap override only
# when explicitly requested, and honour a supplied options file first.
if [[ -z "${IDEA_VM_OPTIONS:-}" && -n "${IDEA_HEAP_MB:-}" ]]; then
    heap_mib="$IDEA_HEAP_MB"
    if [[ ! "$heap_mib" =~ ^[1-9][0-9]{2,4}$ ]] \
        || (( heap_mib < 512 || heap_mib > 32768 )); then
        echo 'IDEA_HEAP_MB must be an integer from 512 to 32768.' >&2
        exit 1
    fi
    options_dir="${XDG_CACHE_HOME:-${HOME:?}/.cache}/intellij-docker"
    mkdir -p -- "$options_dir"
    temporary="$(mktemp "$options_dir/vmoptions.XXXXXX")"
    trap 'rm -f -- "$temporary"' EXIT
    awk '!/^-Xms/ && !/^-Xmx/' "$idea_install_dir/bin/idea64.vmoptions" > "$temporary"
    printf '\n-Xms128m\n-Xmx%sm\n' "$heap_mib" >> "$temporary"
    export IDEA_VM_OPTIONS="$options_dir/idea64.vmoptions"
    mv -- "$temporary" "$IDEA_VM_OPTIONS"
fi

exec "$idea_install_dir/bin/idea.sh" "$@"
