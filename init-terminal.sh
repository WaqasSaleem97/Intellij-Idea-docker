#!/usr/bin/env bash
# LinuxServer runs this after its built-in init steps and before the desktop.
set -euo pipefail

terminal_user="${TERMINAL_USER:-abc}"
if [[ ! "$terminal_user" =~ ^[A-Za-z0-9_.-]+$ ]]; then
    echo 'TERMINAL_USER must contain only letters, numbers, underscores, dots, or hyphens.' >&2
    exit 1
fi

# Keep Webtop's abc account and its persistent home directory.
desktop_home="$(getent passwd abc | cut -d: -f6)"
[[ -n "$desktop_home" && -d "$desktop_home" ]]
bashrc="$desktop_home/.bashrc"
if [[ ! -e "$bashrc" ]]; then
    if [[ -f /etc/skel/.bashrc ]]; then
        cp /etc/skel/.bashrc "$bashrc"
    else
        touch "$bashrc"
    fi
    chown "abc:$(id -gn abc)" "$bashrc"
fi

begin='# >>> intellij-docker terminal prompt >>>'
end='# <<< intellij-docker terminal prompt <<<'
temporary="$(mktemp)"
trap 'rm -f -- "$temporary"' EXIT

# Replace our own block on restart, preserving the rest of the user's file.
awk -v begin="$begin" -v end="$end" '
    $0 == begin { managed = 1; next }
    $0 == end { managed = 0; next }
    !managed { print }
' "$bashrc" > "$temporary"
{
    printf '%s\n' "$begin"
    printf '%s\n' 'if [[ $- == *i* ]] && [[ $(id -un) == abc ]]; then'
    printf "    PS1='%s%s'\n" "$terminal_user" '@\h:\w\$ '
    printf '%s\n' 'fi' "$end"
} >> "$temporary"
cat "$temporary" > "$bashrc"
