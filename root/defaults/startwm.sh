#!/usr/bin/env bash
set -euo pipefail

# Use the package's menu/startup even with a persistent home from XFCE.
exec dbus-launch --exit-with-session /usr/bin/openbox \
    --sm-disable --config-file /etc/xdg/openbox/rc.xml \
    --startup /usr/local/bin/idea
