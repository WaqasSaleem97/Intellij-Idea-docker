FROM ghcr.io/linuxserver/baseimage-selkies:ubunturesolute

ARG IDEA_VERSION=2026.2.3
ARG INSTALL_BROWSER=true

USER root

# Keep the streaming/Openbox base; add only the development tools we need.
RUN set -eu; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
       ca-certificates curl git openjdk-21-jdk-headless \
       libxext6 libxrender1 libxtst6 libxi6 libfreetype6; \
    case "$INSTALL_BROWSER" in \
      true) add-apt-repository -y ppa:xtradeb/apps; \
            apt-get update; \
            DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends chromium; \
            sed -i 's|^Exec=[^ ]*|Exec=/usr/local/bin/browser|' /usr/share/applications/chromium.desktop ;; \
      false) ;; \
      *) echo 'INSTALL_BROWSER must be true or false' >&2; exit 1 ;; \
    esac; \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*.deb

# Download, verify and extract in one layer: the archive is not kept in the image.
RUN set -eu; \
    case "$(dpkg --print-architecture)" in \
      arm64) archive="idea-${IDEA_VERSION}-aarch64.tar.gz" ;; \
      amd64) archive="idea-${IDEA_VERSION}.tar.gz" ;; \
      *) echo 'Only ARM64 and AMD64 are supported' >&2; exit 1 ;; \
    esac; \
    cd /tmp; \
    curl -fL --retry 3 -o "$archive" "https://download.jetbrains.com/idea/$archive"; \
    curl -fL --retry 3 -o "$archive.sha256" "https://download.jetbrains.com/idea/$archive.sha256"; \
    sha256sum -c "$archive.sha256"; \
    mkdir -p /opt/idea; \
    tar -xzf "$archive" -C /opt/idea --strip-components=1; \
    rm "$archive" "$archive.sha256"; \
    jdk_dir="$(dirname "$(dirname "$(readlink -f /usr/bin/javac)")")"; \
    ln -s "$jdk_dir" /opt/jdk; \
    sed -i \
      -e 's|<file>menu.xml</file>|<file>/defaults/menu.xml</file>|g' \
      -e 's|</keyboard>|<keybind key="A-F1"><action name="ShowMenu"><menu>root-menu</menu></action></keybind></keyboard>|' \
      /etc/xdg/openbox/rc.xml

ENV JAVA_HOME=/opt/jdk \
    TITLE="IntelliJ IDEA" \
    PIXELFLUX_WAYLAND=false \
    SELKIES_DESKTOP=false \
    START_DOCKER=false

COPY --chmod=0755 idea-launcher.sh /usr/local/bin/idea
COPY --chmod=0755 browser.sh /usr/local/bin/browser
COPY --chmod=0755 root/defaults/startwm.sh /defaults/startwm.sh
COPY root/defaults/menu.xml /defaults/menu.xml
COPY intellij-idea.desktop /usr/share/applications/intellij-idea.desktop
COPY --chmod=0755 init-terminal.sh /custom-cont-init.d/10-terminal-prompt

# Keep Selkies authentication, HTTPS, abc/PUID/PGID and /config persistence.
