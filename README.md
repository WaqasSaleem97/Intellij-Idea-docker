# IntelliJ IDEA in Docker on Ubuntu

Updated 30 October 2026. Run IntelliJ IDEA 2026.2.3 through your browser with an Ubuntu container, an Openbox desktop, Git, a headless JDK 21 and Chromium. Native **ARM64 and AMD64** builds are supported, including Oracle Ampere hosts.

## Smaller image with 90% resource access

The image uses **`ghcr.io/linuxserver/baseimage-selkies:ubunturesolute`**, which supplies streaming and Openbox without the full XFCE application bundle.[1][2] LinuxServer's ready-made IntelliJ image is AMD64-only, so it does not cover the Oracle ARM64 setup.[3]

| Setting | Previous setup | Current default |
| --- | --- | --- |
| Desktop | Ubuntu Webtop with XFCE | Ubuntu Selkies base with Openbox |
| Development JDK | `openjdk-21-jdk` | `openjdk-21-jdk-headless`, including `javac` |
| Container CPU ceiling | 90% of host CPUs after setup | 90% of host CPUs after setup |
| Container RAM ceiling | 90% of host RAM after setup | 90% of host RAM after setup |
| IntelliJ maximum Java heap | Vendor/user configuration | Vendor/user configuration; no project-imposed heap cap |
| Streaming frame rate | Upstream default | Upstream default; no project frame-rate cap |
| Browser | Included | Included; can be omitted at build time |
| Container logs | Docker daemon default | Rotated local logs, 10 MiB × 3 files |

The image leaves out XFCE's session/panel, PDF and image viewers, file manager and archive tools. IntelliJ opens automatically; Chromium starts when you open it. Audio capture starts off and can be enabled in the streaming sidebar.[2][5]

CPU/RAM values are **limits, not reservations or measured idle usage**. The IDE, browser, streaming and build tools share the container budget. The Java heap is only one part of IDE memory use. Setup allows up to 90% of the CPU capacity and total RAM reported by Docker, without fixed 2-core/4-GiB ceilings. IntelliJ uses its normal vendor/user VM configuration unless you explicitly request an override.[4][6] The full IntelliJ application and its bundled JetBrains Runtime remain installed.

## Requirements

- Ubuntu host with Docker Engine and the Docker Compose plugin working for your normal login user.
- ARM64 or AMD64 (`uname -m`).
- An 8-GB or larger host is a comfortable starting point for the IDE and builds. Resource allowances scale with the capacity reported by Docker.
- Allow about 20 GB free working disk for image construction, retained images, dependency caches and projects. This is a planning allowance, not the final image size.
- Internet access for the base image, packages and JetBrains installer.

## 1. Clone and start

In your **Ubuntu host terminal**:

```bash
git clone https://github.com/WaqasSaleem97/Intellij-Idea-docker.git
cd Intellij-Idea-docker
bash setup.sh
```

Run setup as your normal Ubuntu account, without `sudo`. Choose and repeat a browser password of at least 8 letters/numbers. The default browser username is **`admin`**. This password is separate from your Ubuntu SSH/sudo password.

Setup calculates the 90% CPU/RAM allowance on every run, including when upgrading an older light-profile configuration. Existing browser passwords, custom usernames and other settings are retained. The previous generated default username is migrated to `admin`.

The build selects the native JetBrains installer and verifies its SHA-256 checksum before extraction. The compressed installer is removed in the same layer. The IDE version stays pinned; the base tag receives upstream updates when rebuilt with `--pull`.

## 2. Upgrade an existing installation

Save your work. From the repository directory in the **Ubuntu host terminal**:

```bash
git pull origin main
bash setup.sh
```

This rebuilds the smaller image, refreshes the 90% resource allowance and recreates the service using its existing credentials. **Projects and settings under `/config` are retained. Packages installed manually elsewhere, such as Maven, need reinstalling after recreation.** Include tools in the Dockerfile if they must survive future recreation.[1][7]

Old images and build cache can remain on disk after rebuilding. Setup does not delete other projects' images, containers or data.

## 3. Open the desktop and projects

Open **https://localhost:3001** in your host browser, acknowledge the local self-signed certificate notice, and sign in as `admin` with your chosen password. Use `WEBTOP_USER` for a custom login. HTTPS is required for the streaming browser features.[1]

IntelliJ opens automatically. **Right-click the empty desktop**, or press **Alt+F1** inside the session, for the **Development** menu: IntelliJ IDEA, Terminal and Browser. Alt+F1 also opens the menu when the IDE covers the desktop. Run `idea` in the desktop terminal to reopen the IDE.

- Create or clone projects under **`/config/IdeaProjects`**.
- For Java 21 projects, select **JDK 21**, or add **`/opt/jdk`** as the project SDK. The compiler is included; no `JAVA_HOME` exports are needed.
- Use the JDK required by each project's build-tool version. Older Gradle wrappers can need an older JDK; IntelliJ can download project SDKs separately.
- Open **Browser** from the menu, or run `browser` in the desktop terminal. A container application listening on port 4000 is available there at **http://localhost:4000**. Only desktop port 3001 is published to host loopback.

Free core features and subscription/trial requirements follow JetBrains' licensing.[8]

## CPU and RAM: 90% by default

From the repository directory on the **Docker host**:

```bash
# Apply 90% of the host CPU capacity and total RAM.
bash resources.sh

# Inspect current usage.
docker stats --no-stream
```

The script queries the Docker daemon and calculates 90% of its CPU count and total RAM, rounded down to whole MiB for memory. On a 4-core/24-GiB host this allows **3.6 CPU cores and about 21.6 GiB RAM**. It uses the total capacity available to Docker; it does not continually recalculate from currently free RAM.

It preserves credentials and other settings, validates Compose, and updates only this installation's container. Limits are saved in `.env` without restarting or recreating the container. If Docker rejects the update, `.env` is unchanged. Add `--configure-only` to save the allowance without updating a container. The previous `--performance` argument remains a compatibility alias for the same 90% behavior.

The fixed light profile has been removed. Running setup refreshes older 2-core/4-GiB configurations automatically. Compose requires calculated resource values from setup instead of falling back to fixed ceilings.

Host Docker builds started through the shared socket run outside the IDE container; the IDE service's resource settings do not cap the host daemon or its separate build containers.

Container swap is disabled by setting the RAM+swap allowance equal to RAM.[6] Save work before changing the budget of a busy IDE.

### IDE heap and streaming settings

There is no default project override for the IDE heap or streaming frame rate. Leave these optional `.env` values unset or empty to use the vendor/user VM options and upstream streaming defaults:

```dotenv
IDEA_HEAP_MB=
IDEA_FRAMERATE=
```

If you previously entered an explicit low value, remove it or leave it empty to restore those defaults. An existing generated file under `/config/.cache/intellij-docker` is ignored unless a heap override is explicitly requested.

You can still set `IDEA_HEAP_MB` to opt into a custom heap in MiB, or supply a container `IDEA_VM_OPTIONS` file. The latter takes priority. With neither set, IntelliJ handles its normal VM options, including a custom file created through **Help → Edit Custom VM Options**.[4] Save work and run `docker compose up -d` after changing container environment settings; this can recreate the container.

## Optional image without Chromium

Chromium is included for the course's browser-inside-container tasks. If it is not needed, set this in `.env` before building:

```dotenv
INSTALL_BROWSER=false
```

Run `docker compose build --pull`, then `docker compose up -d`. This omits the browser package at build time. Set the value back to `true` and rebuild to restore it.

## Terminal username and hostname

The terminal prompt displays the host user who runs Compose with hostname `ubuntu`, for example `admin@ubuntu:~$`. Compose reads `SUDO_USER`, then `USER`, then falls back to `ubuntu`.[9] The actual desktop account remains `abc`, with home `/config`; `whoami` returns `abc`. Browser credentials are separate.

The initialization script replaces only its marked prompt block in `.bashrc`. Other content and root-shell prompts are preserved.

## Run Docker commands from IntelliJ

The base includes Docker. Compose mounts the host's `/var/run/docker.sock`, so these commands in **IntelliJ's terminal** use the host Docker Engine:[1]

```bash
docker --version
sudo docker images
sudo docker ps
```

Use `sudo` for socket permissions. Socket access gives the desktop host-level Docker control.[10] An extra daemon is not started in the container. If an older installation reports a missing socket, apply the upgrade instructions from the Ubuntu host.

## Fix or reset browser login

Rerunning setup keeps an existing `.env` password. To choose a new one, save work and run from the repository directory on the Ubuntu host:

```bash
git pull origin main
bash reset-login.sh
```

The script sets username `admin`, replaces only browser credentials, and recreates this service with its existing image. It preserves other settings and keeps `.env` at mode 600. It verifies HTTP 401 for anonymous requests and HTTP 200 for the new credentials, without printing the password. Recreation preserves `/config`; manually installed packages elsewhere are lost.

After **Browser login verified successfully**, use a private/InPrivate browser window to avoid cached credentials. On a remote Oracle host, keep using your existing tunnel and desktop URL. Verification checks the service inside the container; a remaining failure can involve the URL, tunnel or cache.

If the script reports shell overrides, run `unset WEBTOP_USER WEBTOP_PASSWORD` before future Compose commands. The host shell can override `.env` values.[9] Do not share `.env` or passwords.

## Persistence, storage and operation

The host's `./config` is mounted as `/config`. Projects, settings, plugins, home-directory dependency caches and downloaded SDKs there survive recreation. Files elsewhere are outside this persistence mapping. Back up `config` before replacing or removing an installation.[1]

From the repository directory on the host:

```bash
docker compose ps
docker compose logs --tail=100 intellij
docker compose stop
docker compose start

# Inspect disk use without removing anything.
docker system df
du -sh config
docker image ls
```

Rotated local logging bounds future container-log growth.[11] Projects and dependency caches can still grow. After verifying the replacement, remove an old image explicitly with `docker image rm <unused-old-image-id>` if it is no longer needed. Docker refuses removal while a container uses it. Rebuilds also leave build cache; deleting shared volumes is not needed to reduce IDE image storage.

To update IntelliJ, set an available `IDEA_VERSION` in `.env`, run `docker compose build --pull`, then `docker compose up -d`. A plain restart cannot change the container environment.[7] For an occupied desktop port, change the mapping to `127.0.0.1:3002:3001` and open `https://localhost:3002`.

## Validation

```bash
python3 -m unittest discover -s tests -p 'test_*.py' -v
```

The workflow builds native AMD64 and ARM64 images, validates Compose and the 90% resource calculation, launches graphical IntelliJ and Chromium windows, checks authentication and host Docker access, and verifies that the default launcher leaves vendor VM options untouched. See [workflow runs](https://github.com/WaqasSaleem97/Intellij-Idea-docker/actions/workflows/validate.yml).

An [unchanged AMD64 baseline build](https://github.com/WaqasSaleem97/Intellij-Idea-docker/actions/runs/40916411973) of the previous Dockerfile measured **8.50 GB**, compared with **8.04 GB** for this image: about **457 MB (5.4%) less uncompressed image storage** with Chromium included. The reduction is modest because IntelliJ and its bundled runtime account for much of the installation. Removing the optional browser can reduce the image further; that variant is not included in these measurements.

The storage comparison was measured on 29 October 2026. It excludes build cache and `/config`; sizes can change with upstream base/package updates.

## Sources

1. [LinuxServer.io Selkies base images and persistence][1]
2. [LinuxServer.io custom images and Openbox startup][2]
3. [LinuxServer.io IntelliJ architecture support][3]
4. [JetBrains custom VM options and Java heap][4]
5. [Selkies streaming settings][5]
6. [Docker CPU, memory and swap limits][6]
7. [Docker Compose recreation and changed configuration][7]
8. [JetBrains IntelliJ installation and requirements][8]
9. [Docker Compose environment interpolation][9]
10. [Docker socket permissions and privileges][10]
11. [Docker local logging and rotation][11]

[1]: https://docs.linuxserver.io/images/docker-baseimage-selkies/
[2]: https://docs.linuxserver.io/selkies/developer-guide/building-images/
[3]: https://docs.linuxserver.io/images/docker-intellij-idea/
[4]: https://www.jetbrains.com/help/idea/tuning-the-ide.html
[5]: https://docs.linuxserver.io/selkies/user-guide/configuration/
[6]: https://docs.docker.com/engine/containers/resource_constraints/
[7]: https://docs.docker.com/reference/cli/docker/compose/up/
[8]: https://www.jetbrains.com/help/idea/installation-guide.html
[9]: https://docs.docker.com/compose/how-tos/environment-variables/variable-interpolation/
[10]: https://docs.docker.com/engine/install/linux-postinstall/
[11]: https://docs.docker.com/engine/logging/drivers/local/
