FROM ubuntu:26.04

ARG OPENCODE_UID=1000
ARG OPENCODE_GID=1000

LABEL org.opencode.docker.uid=${OPENCODE_UID} \
      org.opencode.docker.gid=${OPENCODE_GID}

USER root

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean \
    && DEBIAN_FRONTEND=noninteractive apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        bash \
        build-essential \
        ca-certificates \
        cmake \
        curl \
        dnsutils \
        file \
        git \
        git-lfs \
        iputils-ping \
        jq \
        netcat-openbsd \
        openssh-client \
        passwd \
        pkg-config \
        postgresql-client \
        ripgrep \
        rsync \
        shellcheck \
        sqlite3 \
        tree \
        unzip \
        xz-utils \
        zip \
        openjdk-25-jdk \
        python3 \
        python3-pip \
        python3-venv \
        php8.5-cli \
        php8.5-xdebug \
        php8.5-curl \
        php8.5-mbstring \
        php8.5-xml \
        php8.5-zip \
        php8.5-intl \
        php8.5-sqlite3 \
        php8.5-pgsql \
        php8.5-bcmath \
        php8.5-gd \
        composer \
    && if [ ! -e /usr/bin/php ]; then ln -s php8.5 /usr/bin/php; fi \
    && printf '%s\n' 'zend_extension=xdebug.so' 'xdebug.mode=off' > /etc/php/8.5/mods-available/xdebug.ini

RUN set -eu; \
    node_arch="$(uname -m)"; \
    case "$node_arch" in \
        x86_64|amd64) node_arch=x64 ;; \
        aarch64|arm64) node_arch=arm64 ;; \
        *) echo "unsupported architecture: $node_arch" >&2; exit 1 ;; \
    esac; \
    node_version=$(curl -fsSL https://nodejs.org/dist/index.json 2>/dev/null \
        | grep -oE '"version":"v[0-9.]+"[^}]*"lts":"[^"]+"' \
        | head -n1 \
        | sed -E 's/.*"version":"(v[0-9.]+)".*/\1/'); \
    curl -fsSL "https://nodejs.org/dist/${node_version}/node-${node_version}-linux-${node_arch}.tar.xz" -o /tmp/node.tar.xz \
    && tar -xJf /tmp/node.tar.xz -C /usr/local --strip-components=1 \
    && rm -f /tmp/node.tar.xz

RUN set -eu; \
    export HOME=/tmp/npm-home \
    && mkdir -p "$HOME" \
    && curl -fL --retry 5 -o /tmp/pd.tgz \
        https://git.sorst.net/philipsorst/project-docs.mcp/releases/download/latest/project-docs-mcp.tgz \
    && npm install -g /tmp/pd.tgz \
    && rm -f /tmp/pd.tgz \
    && rm -rf "$HOME"

RUN set -eu; \
    curl -LsSf https://astral.sh/uv/install.sh | sh \
    && install -m 0755 /root/.local/bin/uv /usr/local/bin/uv \
    && install -m 0755 /root/.local/bin/uvx /usr/local/bin/uvx \
    && rm -rf /root/.local

RUN set -eu; \
    export SHELL=/bin/bash \
    && export HOME=/tmp/pnpm-home \
    && export PNPM_HOME=/usr/local/pnpm \
    && mkdir -p "$HOME" \
    && curl -fsSL https://get.pnpm.io/install.sh | sh - \
    && ln -s "$PNPM_HOME/bin/pnpm" /usr/local/bin/pnpm \
    && ln -s "$PNPM_HOME/bin/pnpx" /usr/local/bin/pnpx \
    && pnpm --version \
    && rm -rf "$HOME"

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
    && printf '[init]\n\tdefaultBranch = main\n[safe]\n\tdirectory = *\n[user]\n\tname = OpenCode Agent\n\temail = agent@opencode.docker\n' > /home/opencode/.gitconfig \
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
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    OPENCODE_DISABLE_AUTOUPDATE=true

WORKDIR /workspace
USER opencode

ENTRYPOINT ["opencode"]
CMD ["acp"]