#!/usr/bin/env bash
# Remove this IntelliJ installation. Run from the original installation folder.
# Docker cleanup reference: https://docs.docker.com/reference/cli/docker/compose/down/
set -euo pipefail

fail() {
    printf 'Removal stopped: %s\n' "$*" >&2
    exit 1
}

script_path="$(readlink -f -- "${BASH_SOURCE[0]}")"
project_dir="${script_path%/*}"
config_dir="$project_dir/config"

# A misplaced script must not erase a home directory or a system directory.
case "$project_dir" in
    /|/home|/root|/tmp|/var|/etc|/usr|/opt)
        fail 'Put remove.sh inside the IntelliJ installation folder.' ;;
esac
if [[ "$project_dir" == "$(readlink -f -- "${HOME:?}")" ]]; then
    fail 'The installation folder must not be your home directory.'
fi
[[ -f "$project_dir/compose.yaml" && -f "$project_dir/Dockerfile" ]] \
    || fail 'Expected compose.yaml and Dockerfile beside remove.sh.'
grep -Eq '^FROM (lscr.io/linuxserver/webtop:ubuntu-xfce|ghcr.io/linuxserver/baseimage-selkies:ubunturesolute)$' "$project_dir/Dockerfile" \
    || fail 'This does not look like the supplied IntelliJ package.'
[[ ! -L "$config_dir" ]] || fail 'config is a symbolic link; its external data needs manual review.'

# Refuse to recursively delete a mounted directory, including bind mounts.
while read -r mount_id parent_id device_id mount_root mount_target remainder; do
    printf -v mount_target '%b' "$mount_target"
    if [[ "$mount_target" == "$config_dir" || "$mount_target" == "$config_dir/"* ]]; then
        fail "Unmount $mount_target before deleting the IntelliJ data."
    fi
done < /proc/self/mountinfo

cd -- "$project_dir"
docker compose version >/dev/null
docker info >/dev/null

# Cleanup must also work if setup stopped before writing .env.
# These values only let Compose parse the file; no container is started.
if [[ ! -f .env ]]; then
    export PUID="${PUID:-$(id -u)}"
    export PGID="${PGID:-$(id -g)}"
    export WEBTOP_PASSWORD="${WEBTOP_PASSWORD:-removal-only-placeholder}"
fi

compose=(docker compose --project-directory "$project_dir" -f "$project_dir/compose.yaml")
services="$("${compose[@]}" config --services)"
[[ "$services" == 'intellij' ]] \
    || fail 'The Compose file must contain only the intellij service.'

printf '\nThis permanently removes:\n'
printf '  - The IntelliJ Compose container, network, local image, and managed volumes.\n'
printf '  - Projects, IDE settings, plugins, and caches under %s\n' "$config_dir"
printf '  - This package\047s setup files, credentials, and remove.sh.\n'
printf '\nInstallation folder: %s\n' "$project_dir"
printf 'Back up any projects you want to keep before continuing.\n\n'
if ! read -r -p 'Type DELETE to continue: ' confirmation || [[ "$confirmation" != 'DELETE' ]]; then
    printf 'Cancelled. Nothing was removed.\n'
    exit 0
fi

# Container-created files may be owned by root. Keep Docker in the current
# user's context; elevate only the explicitly scoped filesystem deletions.
delete_files=(rm)
if (( EUID != 0 )); then
    command -v sudo >/dev/null || fail 'sudo is required to remove container-owned files.'
    # Check the actual cleanup command: sudo -v has different password rules.
    # sudo skips authentication when allowed and prompts when a password is needed.
    delete_files=(sudo -- rm)
    if ! "${delete_files[@]}" --help >/dev/null; then
        fail 'Could not obtain sudo permission for cleanup. Nothing was removed.'
    fi
fi

if ! "${compose[@]}" down --rmi local --volumes; then
    fail 'Docker cleanup failed. Your project files and installer files were kept; resolve the error and rerun.'
fi

"${delete_files[@]}" -rf --one-file-system -- "$config_dir"
"${delete_files[@]}" -f -- \
    "$project_dir/.env" \
    "$project_dir/compose.yaml" \
    "$project_dir/Dockerfile" \
    "$project_dir/intellij-idea.desktop" \
    "$project_dir/init-terminal.sh" \
    "$project_dir/idea-launcher.sh" \
    "$project_dir/browser.sh" \
    "$project_dir/root/defaults/startwm.sh" \
    "$project_dir/root/defaults/menu.xml" \
    "$project_dir/setup.sh" \
    "$project_dir/resources.sh" \
    "$project_dir/reset-login.sh" \
    "$project_dir/README.md" \
    "$project_dir/.dockerignore" \
    "$project_dir/.gitignore" \
    "$script_path"

rmdir -- "$project_dir/root/defaults" "$project_dir/root" 2>/dev/null || true

cd -- /tmp
if rmdir -- "$project_dir" 2>/dev/null; then
    printf '\nIntelliJ installation and its folder were removed.\n'
else
    printf '\nIntelliJ was removed. The folder remains because it contains other files or needs owner permissions: %s\n' "$project_dir"
fi
printf 'Shared base images and Docker build cache are retained.\n'
printf 'You can close the SSH tunnel window on your computer.\n'
