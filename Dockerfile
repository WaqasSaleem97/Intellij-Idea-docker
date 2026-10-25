FROM lscr.io/linuxserver/webtop:ubuntu-xfce

ARG IDEA_VERSION=2026.2.3

USER root

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
       ca-certificates curl git openjdk-21-jdk \
       libxext6 libxrender1 libxtst6 libxi6 libfreetype6 \
    && rm -rf /var/lib/apt/lists/*

# Use the native JetBrains archive for the architecture being built.
RUN set -eu; \
    case "$(dpkg --print-architecture)" in \
      arm64) archive="idea-${IDEA_VERSION}-aarch64.tar.gz" ;; \
      amd64) archive="idea-${IDEA_VERSION}.tar.gz" ;; \
      *) echo "Only ARM64 and AMD64 are supported" >&2; exit 1 ;; \
    esac; \
    cd /tmp; \
    curl -fL --retry 3 -o "$archive" "https://download.jetbrains.com/idea/$archive"; \
    curl -fL --retry 3 -o "$archive.sha256" "https://download.jetbrains.com/idea/$archive.sha256"; \
    sha256sum -c "$archive.sha256"; \
    mkdir -p /opt/idea; \
    tar -xzf "$archive" -C /opt/idea --strip-components=1; \
    rm "$archive" "$archive.sha256"; \
    ln -s /opt/idea/bin/idea.sh /usr/local/bin/idea; \
    jdk_dir="$(dirname "$(dirname "$(readlink -f /usr/bin/javac)")")"; \
    ln -s "$jdk_dir" /opt/jdk

ENV JAVA_HOME=/opt/jdk

COPY intellij-idea.desktop /usr/share/applications/intellij-idea.desktop

# Retain Webtop's entrypoint, desktop session, and streaming services.
