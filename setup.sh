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
        printf 'PUID=%s\nPGID=%s\nWEBTOP_USER=admin\nWEBTOP_PASSWORD=%s\nIDEA_VERSION=2026.2.3\n' \
            "$(id -u)" "$(id -g)" "$webtop_password" > .env
    )
    unset webtop_password webtop_password_confirm
else
    # Upgrade the previous generated default while preserving custom logins.
    if grep -qx 'WEBTOP_USER=waqas' .env; then
        sed -i 's/^WEBTOP_USER=waqas$/WEBTOP_USER=admin/' .env
        echo 'Updated browser login username to admin; password preserved.'
    fi
    echo 'Using your existing .env configuration.'
    echo 'The existing browser password is unchanged. To choose a new one, run bash reset-login.sh.'
fi

# Recalculate the requested 90% budget on every setup run. This also replaces
# any previously generated light-profile limits while preserving credentials.
bash resources.sh --configure-only

mkdir -p config/IdeaProjects
docker compose config --quiet
docker compose build --pull
docker compose up -d
docker compose ps

printf '\nBrowser username configured in the container: '
docker compose exec -T intellij printenv CUSTOM_USER
printf 'Open https://localhost:3001 in your host computer browser.\n'
printf 'Use the browser password from setup; the Ubuntu SSH/sudo password is separate.\n'
