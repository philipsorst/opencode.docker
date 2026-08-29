#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
image="${OPENCODE_DOCKER_IMAGE:-ddr-opencode}"

failures=0

probe() {
    _cmd=$1
    shift
    printf '%s: ' "$_cmd"
    "$_cmd" "$@" 2>&1 | head -n1
}

docker_bin="${DOCKER_BIN:-}"
if [ -z "$docker_bin" ]; then
    for c in /usr/bin/docker /usr/local/bin/docker; do
        if [ -x "$c" ]; then
            docker_bin=$c
            break
        fi
    done
fi
if [ -z "$docker_bin" ]; then
    docker_bin=$(command -v docker || true)
fi

if [ -z "$docker_bin" ]; then
    printf 'ERROR: docker CLI not available.\n'
    exit 1
fi

if ! "$docker_bin" image inspect "$image" >/dev/null 2>&1; then
    printf 'ERROR: docker image %s is not built.\n' "$image"
    printf '      build it with: %s build --pull -t %s --build-arg OPENCODE_UID=$(id -u) --build-arg OPENCODE_GID=$(id -g) --build-arg CACHEBUST=$(date +%%s) %s\n' "$docker_bin" "$image" "$script_dir"
    exit 1
fi

if sh -n "$script_dir/opencode-docker" && sh -n "$script_dir/opencode-docker-acp"; then
    printf 'launcher lint: OK\n'
else
    printf 'launcher lint: FAILED\n'
    failures=$((failures + 1))
fi

if command -v curl >/dev/null 2>&1; then
    node_version=$(curl -fsSL https://nodejs.org/dist/index.json 2>/dev/null \
        | grep -oE '"version":"v[0-9.]+"[^}]*"lts":"[^"]+"' \
        | head -n1 \
        | sed -E 's/.*"version":"(v[0-9.]+)".*/\1/') || node_version=
    if [ -n "$node_version" ]; then
        printf 'node LTS (network): %s\n' "$node_version"
    else
        printf 'WARN: could not resolve the node LTS version from nodejs.org (no network?).\n'
    fi
else
    printf 'WARN: curl not found; skipping node LTS resolution.\n'
fi

printf 'container toolchain checks (%s):\n' "$image"
if "$docker_bin" run --rm --entrypoint bash --user 1000:1000 "$image" -c '
    echo "java: $(java -version 2>&1 | head -1)"
    echo "php: $(php -v | head -1)"
    echo "composer: $(composer --version | head -1)"
    echo "node: $(node --version)"
    echo "python3: $(python3 --version)"
    echo "pip3: $(pip3 --version)"
    echo "uv: $(uv --version)"
    echo "uvx: $(uvx --version)"
    echo "pnpm: $(pnpm --version)"
    echo "opencode: $(opencode --version)"
    echo "go: $(go version)"
    echo "jq: $(jq --version)"
    echo "gcc: $(gcc --version | head -1)"
    echo "cmake: $(cmake --version | head -1)"
    echo "pkg-config: $(pkg-config --version)"
    echo "git-lfs: $(git lfs version | head -1)"
    echo "psql: $(psql --version | head -1)"
    echo "sqlite3: $(sqlite3 --version | head -1)"
    echo "shellcheck: $(shellcheck --version | sed -n "s/^version: /v/p")"
    echo "php modules: $(php -m | grep -icE "^(curl|mbstring|dom|xml|zip|intl|sqlite3|bcmath|gd|pgsql|pdo_pgsql)$") of 11"
    php -r "echo \"php xdebug: \".(extension_loaded(\"xdebug\") ? \"present\" : \"missing\").\" mode=\".var_export(ini_get(\"xdebug.mode\"), true).PHP_EOL;"
    if project-docs-mcp --help >/dev/null 2>&1; then
        echo "project-docs-mcp: OK"
    else
        echo "project-docs-mcp: FAILED"
        exit 1
    fi
'; then
    printf 'container checks: OK\n'
else
    printf 'container checks: FAILED\n'
    failures=$((failures + 1))
fi

if [ "$failures" -ne 0 ]; then
    printf '%d failure(s) found.\n' "$failures"
    exit 1
fi
printf 'All checks passed.\n'
