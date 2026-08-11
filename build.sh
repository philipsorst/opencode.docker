#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
image="${OPENCODE_DOCKER_IMAGE:-ddr-opencode}"

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

"$docker_bin" build --pull -t "$image" \
    --build-arg "OPENCODE_UID=$(id -u)" \
    --build-arg "OPENCODE_GID=$(id -g)" \
    --build-arg "CACHEBUST=$(date +%s)" "$script_dir"
