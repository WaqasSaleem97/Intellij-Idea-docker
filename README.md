# IntelliJ IDEA in Docker on Ubuntu

Updated 26 October 2026. This custom image combines LinuxServer.io's Ubuntu
XFCE Webtop desktop with JetBrains' native IntelliJ IDEA 2026.2.3 installer.
It builds on ARM64 or AMD64 without cross-architecture emulation.
The IDE, terminal, Java compiler, projects and builds run in the container on
your Ubuntu computer. Open its desktop through a browser on that same computer.

LinuxServer's standalone `intellij-idea` image is currently AMD64-only. Its
`webtop` image supports ARM64 and AMD64, including an `ubuntu-xfce` flavor.
JetBrains publishes an ARM64 Linux installer. Sources: [Webtop documentation][1],
[standalone image architecture table][2], [JetBrains release metadata][3].

## Requirements

- Ubuntu computer with Docker Engine and the Docker Compose plugin working
  for your normal login user.
- ARM64 or AMD64; check `uname -m`.
- A browser on the same computer as the Docker host.
- Outbound internet access for the base image, Ubuntu packages and JetBrains
  download. The IDE archive alone is about 1.6 GB; the full image is larger.
- As a practical starting budget, leave 8 GB RAM and at least 20 GB free disk
  available for this setup, image-building space and a small project. This is a
  suggested budget, not a measured requirement. JetBrains lists 4 CPU cores,
  8 GB total RAM, 3 GB available for IDE processes and 10 GB IDE disk space.[4]

Setup calculates limits of 90% of the Docker host's CPU capacity and total RAM.
On a 4-core/24-GiB server, that is 3.6 CPU cores and approximately 21.6 GiB RAM;
the exact RAM limit uses Docker's reported total and rounds down to whole MiB.
These are usage ceilings, not reservations: the container consumes resources
as needed and shares the host with other workloads. This does not reserve 10%
for the OS or guarantee that 90% is currently free. Disk space and network
bandwidth are not limited by this setting.[9]

## 1. Clone and start the environment

In your Ubuntu host terminal:

```bash
git clone https://github.com/WaqasSaleem97/Intellij-Idea-docker.git
cd Intellij-Idea-docker
bash setup.sh
```

Run `setup.sh` as your normal Ubuntu user. It asks for a browser password,
records your UID/GID, creates the persistent project directory, builds the image
and starts the container. Use at least 8 letters/numbers for the password.

The default browser username is **admin**. Setup updates the previous generated
default username to `admin` in an existing `.env` and keeps its password.
Other custom usernames and existing resource settings are preserved.

Setup initializes the 90% resource limits when any resource key is missing.
Once all three resource keys exist, later setup runs keep their values.
The first build downloads several GB. The Dockerfile checks the IDE archive
against JetBrains' published SHA-256 checksum before extracting it.

## 2. Open the desktop locally

Open **https://localhost:3001** in your host computer's browser. Webtop serves a
self-signed certificate by default. Acknowledge that notice for this local
desktop address, then log in with username **admin** and your chosen password.
Use your configured `WEBTOP_USER` instead if you have a custom login.
Use HTTPS because the streaming client requires a secure context.[1]

Compose publishes desktop port 3001 on the Docker host's loopback address.[6]
For web applications running inside this desktop, open the browser inside the
container. For example, a Node.js application listening on port 4000 is available
there at `http://localhost:4000`.

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

## Terminal username and hostname

The Bash terminal prompt displays the host user who runs `docker compose up -d`
with the container hostname `ubuntu`. For example, host user `admin` sees
`admin@ubuntu:~$`, and host user `ubuntu` sees `ubuntu@ubuntu:~$`.
Compose reads the username from the host's `SUDO_USER` when set, otherwise
`USER`, with `ubuntu` as a fallback when neither is available.[7]

This is a prompt display setting. Webtop's desktop still runs as its built-in
Linux account `abc`, so `whoami` returns `abc` and its home remains `/config`.
Root shells retain their normal root prompt. Browser login credentials are
configured separately through `WEBTOP_USER` and `WEBTOP_PASSWORD`.[1]

The startup script updates a marked block in `/config/.bashrc`, including for
existing installations, and preserves the rest of that file. It runs through
LinuxServer's custom initialization hook before the desktop starts.[8]

To apply this update to an existing installation, run from your repository
directory:

```bash
git pull --ff-only
docker compose up -d --build
```

Then open a new terminal in the browser desktop or IntelliJ. The rebuild is
needed once to include the new startup script; subsequent starts can use
`docker compose up -d`. Container recreation retains `/config`, but packages
installed manually inside the previous container (such as Maven) must be
reinstalled or included in your Dockerfile before recreation.

## Run Docker commands from IntelliJ

The Webtop base image already includes Docker.[14] Compose shares the Ubuntu
host's `/var/run/docker.sock` with the container, so commands in the desktop or
IntelliJ terminal manage the host's images and containers.

In the **IntelliJ terminal**, run:

```bash
sudo docker images
sudo docker ps
```

Use `sudo` because the socket is normally owned by root and the host's Docker
group; the desktop account may not belong to that group.[13]

To apply the socket mount to an **existing installation**, save your work and
run these commands from the repository directory in your **Ubuntu host terminal**:

```bash
git pull origin main
sudo systemctl start docker
docker compose up -d --force-recreate intellij
```

Reopen `https://localhost:3001`, launch IntelliJ and run `sudo docker images`
again. This socket-only update does not require an image rebuild. Recreation
keeps projects and settings under `/config`; packages installed manually
outside that directory must be reinstalled.

If Docker reports that `/var/run/docker.sock` does not exist, check that you
applied the update from the host and recreated the container. A permission
error calls for `sudo docker images` inside IntelliJ.

Access to this socket gives the desktop container root-level control through
the host's Docker Engine.[13] This configuration uses the standard Ubuntu
Docker Engine socket and shares the host's Docker installation.[14]

## Persistence

The container's home directory is `/config`, backed by the package's `config`
folder on your server. Projects under `/config/IdeaProjects`, IDE settings,
plugins, and normal home-directory caches persist when the container is
recreated.[1]

Keep new work under `/config`. Files saved elsewhere in the container's writable
layer are not covered by this persistence mapping. Back up the `config` directory.

## Operation

Run these from the repository directory on the Ubuntu host:

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

To change browser credentials, edit `.env`, then run `docker compose up -d`.
For CPU/RAM limits, use the live-update instructions below. To install a newer
IntelliJ version, set `IDEA_VERSION`
to an available JetBrains unified-release version in `.env`, then run:

```bash
docker compose build --pull
docker compose up -d
```

Do not use `docker compose pull` as the update mechanism for this custom image;
rebuild it instead. The base image uses a rolling `ubuntu-xfce` tag, while the
IDE version is pinned. Update the IDE through the Dockerfile build.

If desktop port 3001 is already occupied on the host, change its Compose mapping
to `127.0.0.1:3002:3001`, run `docker compose up -d` and open
`https://localhost:3002`.

## Allow up to 90% of host CPU and RAM

For an existing installation, run these commands in the repository directory
on the Ubuntu host, using its terminal:

```bash
git pull --ff-only
bash resources.sh
docker stats --no-stream "$(docker compose ps -q intellij)"
```

`resources.sh` reads the CPU count and total RAM from the Docker daemon. It
replaces the old resource values in `.env`, preserving credentials and other
settings, and applies them to this project's existing `intellij` container with
`docker update`. A running container stays running, a stopped container stays
stopped, and manually installed tools remain in place. There is no rebuild or
container recreation for this resource update.[10]

The script writes `IDEA_CPU_LIMIT`, `IDEA_MEMORY_LIMIT`, and
`IDEA_MEMORY_SWAP_LIMIT`. The RAM+swap limit equals the RAM limit, disabling
container swap to avoid disk swapping during heavy builds. The limits cover
the entire container: IntelliJ, the desktop, Chromium, and Java builds together.
They do not increase IntelliJ's own JVM heap setting.[9][11]

CPU was previously uncapped; the 90% setting introduces a CPU ceiling. The
increase is in the old 8-GiB RAM cap. If other services also need substantial
RAM, this setting alone cannot prevent host memory pressure, and it does not
continuously recalculate from currently free memory. Rerun `resources.sh` after
resizing the server to recalculate from its new totals.

Future `docker compose up -d` calls use the saved limits. Compose may recreate
the container when it detects the changed configuration, even after a live
update; use `docker compose stop` / `docker compose start` to stop or resume
the same container. Normal recreation retains `/config` but loses manually
installed packages outside it. Until setup or `resources.sh` has configured the
new keys, Compose keeps its previous fallback of 8 GiB RAM and uncapped CPU.[12]

## Validation scope

The Compose YAML and shell syntax were checked, and the architecture support,
download URL, and access settings were checked against the primary sources
below. Docker is unavailable in the preparation environment, so this image was
not built or launched here, and it has not been launched on your computer by this documentation update.
The resource script was also checked with simulated Docker responses for the
90% calculation, scoped live updates, credential preservation, and failure handling.

## Sources

1. [LinuxServer.io Webtop: architecture, images, access, and persistence][1]
2. [LinuxServer.io IntelliJ image: supported architectures][2]
3. [JetBrains release API: current IntelliJ release and ARM64 download][3]
4. [JetBrains IntelliJ installation, requirements, runtime, and licensing][4]
6. [Docker: port publishing and loopback bindings][6]
7. [Docker Compose: interpolation from the host shell][7]
8. [LinuxServer.io: custom initialization scripts][8]
9. [Docker: CPU, memory, and swap constraints][9]
10. [Docker: updating a running container's limits][10]
11. [Docker Compose: service CPU, memory, and swap settings][11]
12. [Docker Compose: when up recreates containers][12]
13. [Docker: socket ownership and Docker access privileges][13]
14. [LinuxServer.io: Docker included in the base image and host socket access][14]

[1]: https://docs.linuxserver.io/images/docker-webtop/
[2]: https://docs.linuxserver.io/images/docker-intellij-idea/
[3]: https://data.services.jetbrains.com/products/releases?code=IIU&latest=true&type=release
[4]: https://www.jetbrains.com/help/idea/installation-guide.html
[6]: https://docs.docker.com/engine/network/port-publishing/
[7]: https://docs.docker.com/compose/how-tos/environment-variables/variable-interpolation/
[8]: https://docs.linuxserver.io/general/container-customization/
[9]: https://docs.docker.com/engine/containers/resource_constraints/
[10]: https://docs.docker.com/reference/cli/docker/container/update/
[11]: https://docs.docker.com/reference/compose-file/services/
[12]: https://docs.docker.com/reference/cli/docker/compose/up/
[13]: https://docs.docker.com/engine/install/linux-postinstall/
[14]: https://docs.linuxserver.io/images/docker-baseimage-selkies/#docker-in-docker-dind
