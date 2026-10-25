#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

if (( EUID == 0 )); then
    echo 'Run this script as your normal Ubuntu login user, without sudo.' >&2
    exit 1
fi

case "$(uname -m)" in
    aarch64|arm64|x86_64) ;;
    *) echo 'This setup supports ARM64 and AMD64 hosts.' >&2; exit 1 ;;
esac

docker compose version >/dev/null
docker info >/dev/null

if [[ ! -f .env ]]; then
    read -r -s -p 'Choose a browser login password (at least 8 letters/numbers): ' webtop_password
    printf '\n'
    if [[ ! "$webtop_password" =~ ^[A-Za-z0-9]{8,}$ ]]; then
        echo 'Use at least 8 letters/numbers; rerun setup.sh to try again.' >&2
        exit 1
    fi
    read -r -s -p 'Repeat password: ' webtop_password_confirm
    printf '\n'
    if [[ "$webtop_password" != "$webtop_password_confirm" ]]; then
        echo 'Passwords did not match.' >&2
        exit 1
    fi
    (
        umask 077
        printf 'PUID=%s\nPGID=%s\nWEBTOP_USER=waqas\nWEBTOP_PASSWORD=%s\nIDEA_VERSION=2026.2.3\n' \
            "$(id -u)" "$(id -g)" "$webtop_password" > .env
    )
    unset webtop_password webtop_password_confirm
else
    echo 'Using your existing .env configuration.'
fi

# Set the new default once, including when upgrading an older 8g configuration.
# On later setup runs, retain the already configured resource limits.
if ! grep -Eq '^IDEA_CPU_LIMIT=.+' .env \
    || ! grep -Eq '^IDEA_MEMORY_LIMIT=.+' .env \
    || ! grep -Eq '^IDEA_MEMORY_SWAP_LIMIT=.+' .env; then
    bash resources.sh --configure-only
fi

mkdir -p config/IdeaProjects
docker compose config --quiet
docker compose build --pull
docker compose up -d
docker compose ps

printf '\nBrowser username: waqas (or WEBTOP_USER from your existing .env).\n'
printf 'Create the SSH tunnel described in README.md, then open https://localhost:3001.\n'
