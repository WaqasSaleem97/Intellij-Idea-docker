#!/usr/bin/env bash
set -euo pipefail
image="${1:-intellij-lean:ci}"
container="intellij-smoke-${RANDOM}"
work_dir="$(mktemp -d)"
cleanup() {
    docker rm -f "$container" >/dev/null 2>&1 || true
    rm -rf -- "$work_dir"
}
trap cleanup EXIT
mkdir -p "$work_dir/config"
read -r host_cpus host_memory <<< "$(docker info --format '{{.NCPU}} {{.MemTotal}}')"
cpu_hundredths=$((host_cpus * 90))
printf -v cpu_limit '%d.%02d' "$((cpu_hundredths / 100))" "$((cpu_hundredths % 100))"
memory_mib=$((host_memory / 1024 / 1024 * 90 / 100))
docker run -d --name "$container" --cpus "$cpu_limit" \
    --memory "${memory_mib}m" --memory-swap "${memory_mib}m" \
    --shm-size=1g \
    -e PUID="$(id -u)" -e PGID="$(id -g)" \
    -e TERMINAL_USER=student -e CUSTOM_USER=admin -e PASSWORD=SmokeDemoOnly123 \
    -v "$work_dir/config:/config" \
    -v /var/run/docker.sock:/var/run/docker.sock \
    "$image" >/dev/null

ready=false
for attempt in {1..90}; do
    anonymous="$(docker exec "$container" curl -ks --max-time 3 -o /dev/null -w '%{http_code}' https://127.0.0.1:3001/ || true)"
    if [[ "$anonymous" == 401 ]]; then
        authenticated="$(docker exec "$container" curl -ks --max-time 3 -u admin:SmokeDemoOnly123 -o /dev/null -w '%{http_code}' https://127.0.0.1:3001/ || true)"
        if [[ "$authenticated" == 200 ]]; then ready=true; break; fi
    fi
    sleep 2
done
if [[ "$ready" != true ]]; then
    docker logs --tail=150 "$container"
    echo 'Desktop authentication did not become ready.' >&2
    exit 1
fi

window=false
for attempt in {1..90}; do
    if docker exec "$container" xdotool search --class jetbrains-idea >/dev/null 2>&1; then
        window=true
        break
    fi
    sleep 2
done
if [[ "$window" != true ]]; then
    docker logs --tail=150 "$container"
    echo 'IntelliJ did not open a graphical window.' >&2
    exit 1
fi

docker exec "$container" java --version
docker exec "$container" javac --version
docker exec "$container" git --version
docker exec "$container" chromium --version
docker exec -d "$container" s6-setuidgid abc /usr/local/bin/browser about:blank
browser_window=false
for attempt in {1..45}; do
    if docker exec "$container" xdotool search --class '[Cc]hromium' >/dev/null 2>&1; then
        browser_window=true
        break
    fi
    sleep 2
done
[[ "$browser_window" == true ]] || { echo 'Chromium did not open a graphical window.' >&2; exit 1; }
docker exec "$container" docker version --format '{{.Server.Version}}'
docker exec "$container" test ! -f /config/.cache/intellij-docker/idea64.vmoptions
read -r actual_cpu actual_memory <<< "$(docker inspect --format '{{.HostConfig.NanoCpus}} {{.HostConfig.Memory}}' "$container")"
[[ "$actual_cpu" == "$((host_cpus * 900000000))" ]]
[[ "$actual_memory" == "$((memory_mib * 1024 * 1024))" ]]
docker exec "$container" grep -F -- 'student' /config/.bashrc
docker exec "$container" bash -c '! pgrep -x xfce4-session && ! pgrep -x xfwm4'

printf '\nImage storage (bytes):\n'
docker image inspect "$image" --format '{{.Size}}'
printf '\nSampled container usage with IntelliJ and Chromium open:\n'
docker stats --no-stream --format '{{.CPUPerc}} CPU; {{.MemUsage}} RAM' "$container"
printf '\n%s\n' 'PASS: authentication, IntelliJ/Chromium GUI, 90% resource budget, vendor VM options, Java tools and host Docker access.'
