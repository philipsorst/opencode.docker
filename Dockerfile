FROM ubuntu:26.04

ARG OPENCODE_UID=1000
ARG OPENCODE_GID=1000

USER root

RUN DEBIAN_FRONTEND=noninteractive apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        curl \
        git \
        openssh-client \
        passwd \
        ripgrep \
        unzip \
        xz-utils \
        zip \
        openjdk-25-jdk \
        php8.5-cli \
        php8.5-xdebug \
        php8.5-curl \
        php8.5-mbstring \
        php8.5-xml \
        php8.5-zip \
        php8.5-intl \
        php8.5-sqlite3 \
        php8.5-bcmath \
        php8.5-gd \
        composer \
    && rm -rf /var/lib/apt/lists/* \
    && if [ ! -e /usr/bin/php ]; then ln -s php8.5 /usr/bin/php; fi \
    && printf '%s\n' 'zend_extension=xdebug.so' 'xdebug.mode=off' > /etc/php/8.5/mods-available/xdebug.ini

RUN set -eu; \
    node_arch="$(uname -m)"; \
    case "$node_arch" in \
        x86_64|amd64) node_arch=x64 ;; \
        aarch64|arm64) node_arch=arm64 ;; \
        *) echo "unsupported architecture: $node_arch" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://nodejs.org/dist/v24.19.0/node-v24.19.0-linux-${node_arch}.tar.xz" -o /tmp/node.tar.xz \
    && tar -xJf /tmp/node.tar.xz -C /usr/local --strip-components=1 \
    && rm -f /tmp/node.tar.xz

RUN groupadd -o --gid "${OPENCODE_GID}" opencode \
    && useradd -o \
        --uid "${OPENCODE_UID}" \
        --gid "${OPENCODE_GID}" \
        --create-home \
        --shell /bin/bash \
        opencode \
    && mkdir -p \
        /home/opencode/.config/opencode \
        /home/opencode/.local/share/opencode \
        /home/opencode/.local/state/opencode \
        /home/opencode/.cache/opencode \
        /workspace \
    && chown -R "${OPENCODE_UID}:${OPENCODE_GID}" /home/opencode \
    && chmod -R a+rwX /home/opencode /workspace

ARG CACHEBUST
RUN echo "cachebust=${CACHEBUST}" \
    && curl -fsSL https://opencode.ai/install \
        | bash -s -- --no-modify-path \
    && install -m 0755 /root/.opencode/bin/opencode /usr/local/bin/opencode \
    && rm -rf /root/.opencode

ENV HOME=/home/opencode \
    XDG_CONFIG_HOME=/home/opencode/.config \
    XDG_DATA_HOME=/home/opencode/.local/share \
    XDG_STATE_HOME=/home/opencode/.local/state \
    XDG_CACHE_HOME=/home/opencode/.cache \
    OPENCODE_DISABLE_AUTOUPDATE=true

WORKDIR /workspace
USER opencode

ENTRYPOINT ["opencode"]
CMD ["acp"]