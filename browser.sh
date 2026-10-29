#!/usr/bin/env bash
set -euo pipefail
if ! command -v chromium >/dev/null; then
    echo 'This image was built without Chromium. Rebuild with INSTALL_BROWSER=true to include it.' >&2
    exit 1
fi
# Chromium's namespace sandbox is unavailable in the ordinary desktop container.
exec chromium --no-sandbox --no-first-run "$@"
