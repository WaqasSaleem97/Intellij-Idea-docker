# IntelliJ IDEA in Docker on Oracle Ubuntu

Prepared 22 October 2026. This custom image combines LinuxServer.io's Ubuntu
XFCE Webtop desktop with JetBrains' native IntelliJ IDEA 2026.2.3 installer.
It builds on Oracle Ampere ARM64 or AMD64 without cross-architecture emulation.
The IDE, terminal, Java compiler, projects, and builds run on the Oracle server;
you use the desktop through a browser on your computer.

LinuxServer's standalone `intellij-idea` image is currently AMD64-only. Its
`webtop` image supports ARM64 and AMD64, including an `ubuntu-xfce` flavor.
JetBrains publishes an ARM64 Linux installer. Sources: [Webtop documentation][1],
[standalone image architecture table][2], [JetBrains release metadata][3].

## Requirements

- Ubuntu server with Docker Engine and the Docker Compose plugin already working
  for your normal login user. Check `docker info` and `docker compose version`.
- ARM64 or AMD64; check `uname -m`.
- Working SSH access from your computer to the server.
- Outbound internet access for the base image, Ubuntu packages, and JetBrains
  download. The IDE archive alone is about 1.6 GB; the full image is larger.
- As a practical starting budget, leave 8 GB RAM and at least 20 GB free disk
  available for this setup, image-building space, and a small project. This is a
  suggested budget, not a measured requirement. JetBrains lists 4 CPU cores,
  8 GB total RAM, 3 GB available for IDE processes, and 10 GB IDE disk space.[4]

For a 4-core/24-GB server, the included 8-GB container memory cap is a reasonable
starting point if that much memory is free. CPU is not capped. Other containers,
especially active LLM inference, can compete with the IDE for resources.

## 1. Copy and extract the package

Download `intellij-oracle-docker.zip` to your computer. In Windows PowerShell,
copy it to the server using your usual SSH key:

```powershell
scp -i "C:\path\oracle.key" "$HOME\Downloads\intellij-oracle-docker.zip" ubuntu@YOUR_SERVER_IP:~/
```

Replace the key path and server IP. If your SSH configuration already selects
the key, omit `-i` and its path.

In your server's SSH terminal:

```bash
sudo apt-get update
sudo apt-get install -y unzip
unzip intellij-oracle-docker.zip
cd intellij-oracle-docker
bash setup.sh
```

Run `setup.sh` as your normal Ubuntu user. It asks for a browser password,
records your UID/GID, creates the persistent project directory, builds the image,
and starts the container. Use at least 8 letters/numbers for the password; this
simple format avoids Compose interpolation and quoting mistakes. Existing `.env`
settings are kept on reruns.

The first build downloads several GB. The Dockerfile checks the IDE archive
against JetBrains' published SHA-256 checksum before extracting it.

## 2. Open an SSH tunnel from your computer

In Windows PowerShell, run:

```powershell
ssh -i "C:\path\oracle.key" -N -o ExitOnForwardFailure=yes -L 127.0.0.1:3001:127.0.0.1:3001 ubuntu@YOUR_SERVER_IP
```

Keep this terminal open. An idle terminal with no output is normal. The tunnel
uses the server's existing SSH access; it does not require an Oracle ingress
rule for port 3001. OpenSSH documents `-L` for local port forwarding.[5]

Open **https://localhost:3001** in your computer's browser. Webtop serves a
self-signed certificate by default. Acknowledge that warning for this local,
SSH-tunnelled address, then log in with username **waqas** and your chosen
password. Use HTTPS, because the streaming client requires a secure context.[1]

The Compose mapping binds the service to the server's loopback address.
Keep that mapping for this SSH access method. For public web access, use an
authenticated HTTPS reverse proxy or a VPN; Webtop's maintainer advises against
exposing its desktop directly with only the built-in basic authentication.[1][6]

## 3. Start IntelliJ and create a project

In the browser desktop, find **IntelliJ IDEA** in the applications menu, or open
the desktop's terminal and run:

```bash
idea
```

Run this command in the browser desktop terminal so it has access to the
graphical session. Complete JetBrains' first-run screens.

- Create or clone projects under **/config/IdeaProjects**.
- For Java projects, select **JDK 21**. If it is not detected, choose **Add JDK**
  and select **/opt/jdk**.
- The image includes Git and OpenJDK 21. The IDE retains its bundled JetBrains
  Runtime. Add Maven/Gradle wrappers to projects that need those build tools.
- If an IDE shortcut is intercepted by your browser, use the IDE menu or adjust
  that shortcut.

IntelliJ's core features remain free; Ultimate-only features require the
applicable subscription after the trial. This package does not provide a
license.[4]

## Persistence

The container's home directory is `/config`, backed by the package's `config`
folder on your server. Projects under `/config/IdeaProjects`, IDE settings,
plugins, and normal home-directory caches persist when the container is
recreated.[1]

Keep new work under `/config`. Files saved elsewhere in the container's writable
layer are not covered by this persistence mapping. Back up the `config` directory.

## Operation

Run these from the package directory on the server:

```bash
# Status and logs
docker compose ps
docker compose logs --tail=100 intellij

# Stop or resume
docker compose stop
docker compose start

# See current resource usage
docker stats
```

To change the memory cap or browser credentials, edit `.env`, then run
`docker compose up -d`. To install a newer IntelliJ version, set `IDEA_VERSION`
to an available JetBrains unified-release version in `.env`, then run:

```bash
docker compose build --pull
docker compose up -d
```

Do not use `docker compose pull` as the update mechanism for this custom image;
rebuild it instead. The base image uses a rolling `ubuntu-xfce` tag, while the
IDE version is pinned. Update the IDE through the Dockerfile build.

If localhost port 3001 is already occupied on your computer, use local port 3002:

```powershell
ssh -i "C:\path\oracle.key" -N -o ExitOnForwardFailure=yes -L 127.0.0.1:3002:127.0.0.1:3001 ubuntu@YOUR_SERVER_IP
```

Then open `https://localhost:3002`. If port 3001 is occupied on the server,
change the host port in Compose and the remote destination port in the tunnel
to the same unused value.

## Validation scope

The Compose YAML and shell syntax were checked, and the architecture support,
download URL, and access settings were checked against the primary sources
below. Docker is unavailable in the preparation environment, so this image was
not built or launched here, and it has not been deployed to your Oracle server.

## Sources

1. [LinuxServer.io Webtop: architecture, images, access, and persistence][1]
2. [LinuxServer.io IntelliJ image: supported architectures][2]
3. [JetBrains release API: current IntelliJ release and ARM64 download][3]
4. [JetBrains IntelliJ installation, requirements, runtime, and licensing][4]
5. [OpenSSH manual: local TCP forwarding][5]
6. [Docker: port publishing and loopback bindings][6]

[1]: https://docs.linuxserver.io/images/docker-webtop/
[2]: https://docs.linuxserver.io/images/docker-intellij-idea/
[3]: https://data.services.jetbrains.com/products/releases?code=IIU&latest=true&type=release
[4]: https://www.jetbrains.com/help/idea/installation-guide.html
[5]: https://man.openbsd.org/ssh#L
[6]: https://docs.docker.com/engine/network/port-publishing/
