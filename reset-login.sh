#!/usr/bin/env bash
# Reset browser basic-auth credentials on the Docker host, then verify them.
set +x
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

fail() {
    printf 'Login reset stopped: %s\n' "$*" >&2
    exit 1
}

(( $# == 0 )) || fail 'Usage: bash reset-login.sh'
(( EUID != 0 )) || fail 'Run as your normal Ubuntu login user, without sudo.'
[[ -f .env && -f compose.yaml ]] || fail 'Run bash setup.sh first.'
docker compose version >/dev/null
docker info >/dev/null

printf 'This sets the browser username to admin and recreates the intellij container.\n'
printf 'Save your work first. Projects/settings in /config stay; manually installed\n'
printf 'packages and files outside /config are lost when the container is recreated.\n\n'
read -r -s -p 'New browser password (at least 8 letters/numbers): ' webtop_password \
    || fail 'No password was entered. Nothing was changed.'
printf '\n'
[[ "$webtop_password" =~ ^[A-Za-z0-9]{8,}$ ]] \
    || fail 'Use at least 8 letters/numbers. Nothing was changed.'
read -r -s -p 'Repeat new password: ' password_confirm \
    || fail 'Password confirmation was cancelled. Nothing was changed.'
printf '\n'
[[ "$webtop_password" == "$password_confirm" ]] \
    || fail 'Passwords did not match. Nothing was changed.'
unset password_confirm

# Replace only browser credentials; preserve UID/GID, resources, and other settings.
# Do not source .env as shell code or print secrets.
temporary="$(mktemp .env.login.XXXXXX)"
trap 'rm -f -- "$temporary"' EXIT
awk '!/^[[:space:]]*(export[[:space:]]+)?WEBTOP_(USER|PASSWORD)[[:space:]]*[=:]/' .env > "$temporary"
printf 'WEBTOP_USER=admin\nWEBTOP_PASSWORD=%s\n' "$webtop_password" >> "$temporary"

# Override any stale credential variables inherited from the invoking shell.
if [[ -v WEBTOP_USER || -v WEBTOP_PASSWORD ]]; then
    printf 'For future Compose commands, clear shell overrides with: unset WEBTOP_USER WEBTOP_PASSWORD\n'
fi
export WEBTOP_USER=admin WEBTOP_PASSWORD="$webtop_password"
docker compose --env-file "$temporary" config --quiet
mv -- "$temporary" .env

compose=(docker compose --env-file .env)
# A restart keeps the old container environment. Recreate with the existing image.
if ! "${compose[@]}" up -d --no-deps --no-build --pull never --force-recreate intellij; then
    fail 'Credentials were saved in .env, but Docker could not apply them. Resolve the Docker error and rerun this script.'
fi

curl_status() {
    # The bundled curl runs inside the target container, independent of host ports.
    # --disable ignores any user curl configuration; -k accepts its local certificate.
    "${compose[@]}" exec -T intellij curl --disable --insecure --silent \
        --output /dev/null --write-out '%{http_code}' --connect-timeout 2 \
        --max-time 5 "$@" https://127.0.0.1:3001/ 2>/dev/null
}

printf 'Waiting for the desktop to accept the new browser credentials...\n'
anonymous_status=000
authenticated_status=000
for attempt in {1..30}; do
    anonymous_status="$(curl_status)" || anonymous_status=000
    if [[ "$anonymous_status" == 401 ]]; then
        # Send the password through stdin, never through a command-line argument.
        authenticated_status="$(printf 'user = "admin:%s"\n' "$webtop_password" | curl_status --config -)" \
            || authenticated_status=000
        if [[ "$authenticated_status" == 200 ]]; then
            unset webtop_password WEBTOP_PASSWORD
            printf '\nBrowser login verified successfully.\nUsername: admin\n'
            printf 'Open your desktop URL in a new private/InPrivate browser window and use the new password.\n'
            exit 0
        fi
    elif [[ "$anonymous_status" == 200 ]]; then
        fail 'The desktop is responding without authentication. Login protection was not verified; check the container configuration.'
    fi
    sleep 2
done

unset webtop_password WEBTOP_PASSWORD
printf 'Last HTTP status: anonymous=%s, authenticated=%s\n' \
    "$anonymous_status" "$authenticated_status" >&2
fail 'Login could not be verified. Credentials remain saved in .env. Check docker compose ps and docker compose logs --tail=100 intellij; do not share your password or .env.'
