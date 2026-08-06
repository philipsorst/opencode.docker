# AGENTS.md

Guidance for AI coding agents working in this repository.

## What this project is

A self-updating launcher that runs the OpenCode AI agent (`opencode acp`, the ACP
server, used as the backend for JetBrains/other IDE integrations) inside a
sandboxed, general-purpose dev container.

- `Dockerfile` - builds the `ddr-opencode` image: Ubuntu 26.04 (resolute) LTS
  base, OpenJDK 25 (LTS), PHP 8.5 + xdebug, Composer, common CLI tools, and the
  OpenCode binary. Zero third-party package repos (until PHP 8.6 needs ondrej/sury).
- `opencode-acp-docker` - POSIX `sh` launcher (the user-facing entry point).
  Ensures the image exists/fresh, validates the host OpenCode auth, then
  `docker run`s the ACP server against the current directory.

## Key facts / gotchas

- Base `ubuntu:26.04` already contains an `ubuntu` user with UID/GID `1000`.
  That is why `groupadd`/`useradd` use the `-o` (allow duplicate ids) flag:
  `groupadd -o --gid "${OPENCODE_GID}"` + `useradd -o ...`. Do not remove `-o`.
- The host project dir is bind-mounted read-write and the container runs with
  `--user "$(id -u):$(id -g)"` from the launcher, so files the agent creates
  belong to the host user. `OPENCODE_UID`/`OPENCODE_GID` args default to `1000`
  and match `home/opencode` ownership inside the image.
- The image ENTRYPOINT is `opencode`. To run custom commands for verification
  use `docker run --rm --entrypoint bash ... <image> -c '...'`.
- Xdebug is installed with `xdebug.mode=off` (passive). On-demand enablement:
  `XDEBUG_MODE=coverage phpunit`, `XDEBUG_MODE=debug php ...`, etc. The mode
  setting lives in `/etc/php/8.5/mods-available/xdebug.ini`.
- The launcher mounts the host `$XDG_DATA_HOME/opencode` (default
  `~/.local/share/opencode`) into the container so OpenCode reuses the host's
  `auth.json`, and mounts the host `$XDG_STATE_HOME/opencode` (default
  `~/.local/state/opencode`) so sessions/history persist across runs (it is
  `mkdir -p`'d on the host if missing). The launcher aborts only if the data
  directory or `auth.json` is missing. Config and cache are intentionally NOT
  mounted (ephemeral per-container).
- `php` resolves to 8.5 via a conditional symlink (`if [ ! -e /usr/bin/php ];
  then ln -s php8.5 /usr/bin/php; fi`) - Ubuntu does not always register the
  unversioned binary when only `php8.5-*` packages are installed.

## Build cache strategy (do not regress)

The Dockerfile is split into layers keyed to how often their inputs change:

1. **Stable layer** - apt install (CLI tools, OpenJDK 25, PHP 8.5 packages,
   `composer`), php symlink, xdebug ini. Cached; refreshed only when the
   `ubuntu:26.04` tag digest moves (launcher passes `--pull`).
2. **User setup layer** - `opencode` user, XDG dirs, perms. Static, cached.
3. **Volatile layer** - starts at `ARG CACHEBUST` (injected by the launcher as
   `--build-arg CACHEBUST=$(date +%s)`). Currently the only instruction is the
   unpinned OpenCode installer, so a fresh OpenCode is fetched on every
   launcher-triggered rebuild. `ARG CACHEBUST` must be *referenced* inside the
   RUN (`echo "cachebust=${CACHEBUST}"`) or it will not invalidate the cache.

Do not re-pin OpenCode to a version: the whole point of the volatile layer is
tracking the fast-moving upstream releases. Do not move slow-moving installs
(apt, composer) into the volatile layer.

## Verification

Build (mirror the launcher exactly):

```sh
docker build --pull -t ddr-opencode --build-arg "CACHEBUST=$(date +%s)" .
```

Smoke-test the toolchain:

```sh
docker run --rm --entrypoint bash --user 1000:1000 ddr-opencode -c '
  java -version 2>&1 | head -1
  php -v | head -1
  composer --version | head -1
  php -m | grep -icE "^(curl|mbstring|dom|xml|zip|intl|sqlite3|bcmath|gd)$"
  php -r "var_dump(extension_loaded(\"xdebug\"), ini_get(\"xdebug.mode\"));"
'
```

Lint the launcher: `sh -n opencode-acp-docker`.

The launcher cannot run end-to-end unless the host has
`~/.local/share/opencode/auth.json` (real OpenCode login).

## How the launcher works

1. Resolves Docker binary (`DOCKER_BIN` override, then common paths).
2. Checks the image via `docker image inspect`. If absent, or if its
   `{{.Created}}` timestamp is older than 86400 seconds, triggers a rebuild.
   Timestamp is parsed with GNU `date -d`, falling back to BSD `date -j -f`
   (nanoseconds stripped) - keep both branches working (macOS support).
3. If a rebuild is needed but no `Dockerfile` is found next to the script,
   it aborts with an error.
4. Runs `docker run --rm --init -i --user $uid:$gid --workdir <cwd>` with the
   project dir and the OpenCode data + state dirs bind-mounted, XDG env vars
   pointing at `/home/opencode`, and `OPENCODE_DISABLE_AUTOUPDATE=true`,
   invoking `acp`.

## Conventions

- No comments in code files unless the user asks for them.
- `set -eu` POSIX sh in the launcher; `printf` over `echo`; no bash-isms.
- Keep the image free of third-party apt repos while Ubuntu ships the needed
  PHP; when PHP 8.6 is required, plan to introduce ondrej/sury for that version.
- Do not commit unless the user asks.