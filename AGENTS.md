# AGENTS.md

Guidance for AI coding agents working in this repository.

## What this project is

A self-updating launcher that runs the OpenCode AI agent (the interactive TUI
by default, or `opencode acp` — the ACP server used as the backend for
JetBrains/other IDE integrations — via the `-acp` wrapper) inside a sandboxed,
general-purpose dev container.

- `Dockerfile` - builds the `ddr-opencode` image: Ubuntu 26.04 (resolute) LTS
  base, OpenJDK 25 (LTS), Node.js (active LTS), Python  ../../3.14 (the distro
  `python3`), PHP 8.5 + xdebug + `pgsql`/`pdo_pgsql`, Composer, `uv` (`uvx`),
  pnpm (official standalone binary), Go (official tarball), the `project-docs-mcp` MCP server (global
  npm install), a native build toolchain, common CLI
  tools, and the OpenCode binary. Zero third-party package repos (until PHP
  8.6 needs ondrej/sury).
- `opencode-docker` - POSIX `sh` launcher (the user-facing entry point).
  Ensures the image exists/fresh, validates the host OpenCode auth, then
  `docker run`s the interactive OpenCode agent against the current directory.
- `opencode-docker-acp` - thin wrapper that re-invokes `opencode-docker` with
  the env var `OPENCODE_DOCKER_COMMAND=acp`, which starts the ACP server
  instead of the interactive TUI (and swaps `-it` for `-i`).
- `validate.sh` - POSIX `sh` validation. Must run where Docker is available:
  it fails hard if the Docker CLI is missing or the `ddr-opencode` image is not
  built, then verifies the toolchain assumptions inside the container (tool
  versions, php modules, xdebug). It also lints the launcher and resolves the
  node active LTS from the network as a reference.

## Key facts / gotchas

- Base `ubuntu:26.04` already contains an `ubuntu` user with UID/GID `1000`.
  That is why `groupadd`/`useradd` use the `-o` (allow duplicate ids) flag:
  `groupadd -o --gid "${OPENCODE_GID}"` + `useradd -o ...`. Do not remove `-o`.
- The host project dir is bind-mounted read-write and the container runs with
  `--user "$(id -u):$(id -g)"` from the launcher, so files the agent creates
  belong to the host user. The launcher builds the image with
  `--build-arg OPENCODE_UID=$(id -u) --build-arg OPENCODE_GID=$(id -g)` (the
  `Dockerfile` defaults remain `1000` for manual builds), and the image labels
  `org.opencode.docker.uid`/`org.opencode.docker.gid` record what it was built
  for: the launcher inspects them and rebuilds on mismatch, so `/home/opencode`
  is always writable by the runtime `--user`. Keep the labels when touching the
  user setup.
- The launcher masks `$project_dir/.env.local`: if that file exists, it
  bind-mounts an empty read-only file (an `mktemp` placeholder) over the path,
  so the agent can never read the real secrets. The container runs as the same
  UID/GID as the host user, so host-side `chmod 000` would not hold (the agent
  could chmod it back through the read-write project mount), and
  deleting/renaming the file would mutate the project; the empty-file overlay
  keeps the path present and `test -f`-compatible so dotenv parsing still
  behaves, while the real content is unreachable and writes fail (ro). Masking
  is unconditional — do not add an opt-out.
- The image ENTRYPOINT is `opencode` with an empty default `CMD`, so a bare
  `docker run` starts the interactive TUI; pass `acp` to run the ACP server.
  To run custom commands for verification use
  `docker run --rm --entrypoint bash ... <image> -c '...'`.
- Ubuntu 26.04 has no `uv` package in its archives, so `uv`/`uvx` are installed
  via the official Astral installer (`https://astral.sh/uv/install.sh`) into
  `/usr/local/bin` in their own unpinned layer (see "Build cache strategy").
- Node.js is installed from the nodejs.org tarballs, not the distro archive,
  because the archive lags the current release line. The version is resolved at
  build time from `https://nodejs.org/dist/index.json` and must be the current
  **active LTS**: the first entry whose `"lts"` is a non-null string
  (grep literally), *not* `dist/latest`, which may be an odd (non-LTS) major.
- Go is installed from the go.dev tarballs into `/usr/local/go` (symlinks in
  `/usr/local/bin`),notthe distro archive ( (which lags the latest release line).
  The version is resolved at build time from `https://go.dev/VERSION?m=text`.
  `/home/opencode/go/bin` is on `PATH` so `go install`'d tools are runnable.

  (The launcher read-write mounts the host `GOMODCACHE`; see the tool-caches bullet.)
- Python is the distro `python3` (3.14, the current stable line, maintained by
  Ubuntu; the sandbox's `uv`/`uvx` reuse it as the default interpreter). Do NOT
  bypass PEP 668 to pip-install globally: the image intentionally keeps the
  system interpreter protected so agents install deps with `uv` or in a
  `venv`.
- The stable apt layer also ships a native build toolchain (`build-essential`,
  `cmake`, `pkg-config`), `git-lfs`, `postgresql-client` (psql), `sqlite3`,
  `shellcheck`, and network debuggers (`iputils-ping`, `dnsutils`,
  `netcat-openbsd`). The user-setup layer seeds `/home/opencode/.gitconfig`
  (generic identity, `init.defaultBranch=main`, `safe.directory = *`) and the
  image exports `LANG`/`LC_ALL=C.UTF-8`; keep all of these in their existing
  layers (never under `CACHEBUST`). The launcher forwards the host git identity
  as `GIT_AUTHOR_*`/`GIT_COMMITTER_*` env when the host has one (overrides the
  seeded identity).
- Xdebug is installed with `xdebug.mode=off` (passive). On-demand enablement:
  `XDEBUG_MODE=coverage phpunit`, `XDEBUG_MODE=debug php ...`, etc. The mode
  setting lives in `/etc/php/8.5/mods-available/xdebug.ini`.
- The launcher mounts the host `$XDG_DATA_HOME/opencode` (default
  `~/.local/share/opencode`) into the container so OpenCode reuses the host's
  `auth.json`, and mounts the host `$XDG_STATE_HOME/opencode` (default
  `~/.local/state/opencode`) so   sessions/history persist across runs (it is
  `mkdir -p`'d on the host if missing). The launcher aborts only if the data
  directory or `auth.json` is missing. Config and cache are intentionally NOT
  mounted (ephemeral per-container), with one exception: if
  `$XDG_CONFIG_HOME/opencode/opencode.docker.json` exists on the host (beside
  `opencode.json`), it is bind-mounted read-only into the container as
  `opencode.json`, so the sandbox gets Docker-specific settings without
  mounting the host's real config.
- The launcher also auto-discovers host tool caches (uv, pip, composer, yarn,
  huggingface, npm, gradle, maven, cargo, go, nuget, pub, both pnpm store
  layouts) and bind-mounts them read-write at the container's default tool
  locations (which align with the container `HOME`/XDG env vars, so no extra
  env is passed). Per tool, the host dir comes from the tool's own env var
  (`UV_CACHE_DIR`, `PIP_CACHE_DIR`, `NPM_CONFIG_CACHE`, `YARN_CACHE_FOLDER`,
  `COMPOSER_CACHE_DIR`, `GRADLE_USER_HOME`, `CARGO_HOME`, `GOMODCACHE`,
  `NUGET_PACKAGES`, `PUB_CACHE`, `HF_HOME`) when set, else the XDG-aware
  default; env-var dirs are created if missing, default paths are mounted only
  if they already exist. Mount args are accumulated newline-separated and
  word-split in the `docker run` line with `IFS` set to a newline, so paths
  with spaces survive.
- `php` resolves to 8.5 via a conditional symlink (`if [ ! -e /usr/bin/php ];
  then ln -s php8.5 /usr/bin/php; fi`) - Ubuntu does not always register the
  unversioned binary when only `php8.5-*` packages are installed.
- The `project-docs-mcp` MCP server (philipsorst's RAG docs-search server,
  `search_project_docs` tool) is installed globally via npm in its own fresh
  tooling layer, from the moving `latest` release tarball at
  `https://git.sorst.net/philipsorst/project-docs.mcp/releases/download/latest/project-docs-mcp.tgz`.
  It needs `OPENROUTER_API_KEY` at runtime (fails loudly on first use
  without it) and indexes into `$XDG_CACHE_HOME/project-docs-mcp/<hash>.sqlite`,
  which is ephemeral per-container like all caches.
- Postgres support comes from `php8.5-pgsql` (enables `pgsql` + `pdo_pgsql`),
  so the agent can run tests against a Postgres published on a shared Docker
  network.
- At runtime the container joins the `development` Docker network (see
  "How the launcher works"), so tests can reach sibling stack services (e.g.
  a compose Postgres) by their compose service/network name instead of
  `localhost`.

## Build cache strategy (do not regress)

The Dockerfile is split into layers keyed to how often their inputs change:

1. **Stable layer** - apt install (CLI tools, OpenJDK 25, PHP 8.5 packages,
   `composer`), php symlink, xdebug ini. Cached; refreshed only when the
   `ubuntu:26.04` tag digest moves (launcher passes `--pull`).
2. **Fresh tooling layers** - one `RUN` each for unpinned Node.js (active LTS,
    version resolved at build time), Go (official tarball from `go.dev`, version
    resolved at build time), `uv`/`uvx` (Astral installer), pnpm
    (official standalone installer from `get.pnpm.io`, which builds a
   self-contained tree under `/usr/local/pnpm` with shims symlinked into
   `/usr/local/bin`), and the `project-docs-mcp` global npm install (moving
   `latest` tarball). None is under `CACHEBUST`: they sit right after the
   stable layer, so they re-resolve their latest versions whenever the
   base/apt content above them changes, while staying cached across
   CACHEBUST-only rebuilds. The pnpm tree is Node-independent and, being
   pnpm >= 10, self-pins per project via `packageManager` in `package.json`,
   so the image just needs a bootstrap install. Note: the get.pnpm.io script
   runs `pnpm setup --force`, which needs `SHELL` set and writes shell
   profile notes into `$HOME` - the layer runs it with a throwaway
   `HOME=/tmp/pnpm-home` so nothing lands in any real profile.
3. **User setup layer** - `opencode` user, XDG dirs, perms. Static, cached.
4. **Volatile layer** - starts at `ARG CACHEBUST` (injected by the launcher as
   `--build-arg CACHEBUST=$(date +%s)`). Its only instruction is the unpinned
   OpenCode installer, so a fresh OpenCode is fetched on every launcher-triggered
   rebuild. `ARG CACHEBUST` must be *referenced* inside the RUN
   (`echo "cachebust=${CACHEBUST}"`) or it will not invalidate the cache.

Do not re-pin OpenCode: the whole point of the volatile layer is tracking the
fast-moving upstream releases. Do not move slow-moving installs (apt, composer)
into the volatile layer, and do not move Node/Go/uv/pnpm under `CACHEBUST` either -
that would re-download their installers on every rebuild for no freshness gain
(they already track their latest when their layer re-runs).

The apt RUN in the stable layer uses two BuildKit cache mounts
(`--mount=type=cache` on `/var/cache/apt` and `/var/lib/apt/lists`) so adding a
package to the list does not re-download the other packages. Two gotchas keep
this working:

- Ubuntu 26.04 defaults `APT::Keep-Downloaded-Packages` to `0` and ships
  `docker-clean` in `/etc/apt/apt.conf.d`, whose post-invoke hooks delete
  `/var/cache/apt/archives/*.deb` after every `apt-get update`/`dpkg` - that
  would empty the cache mount. The Dockerfile removes it (`rm -f
  /etc/apt/apt.conf.d/docker-clean`) first; do not rely on the setting alone
  and do not re-add a lists/archives cleanup (`rm -rf /var/lib/apt/lists/*`)
  inside the RUN, or the cache is lost.
- Cache mounts persist in the BuildKit builder store until `docker builder
  prune`. They are not part of the image layers; the `ubuntu:26.04` base itself
  is only re-pulled because the launcher passes `--pull`.

## Verification

Build (mirror the launcher exactly):

```sh
./build.sh
```

Smoke-test / validate the toolchain:

```sh
./validate.sh
```

`./build.sh` runs the same `docker build --pull -t <image> --build-arg
"OPENCODE_UID=$(id -u)" --build-arg "OPENCODE_GID=$(id -g)" --build-arg
"CACHEBUST=$(date +%s)"` command the launcher uses (honoring
`OPENCODE_DOCKER_IMAGE` and `DOCKER_BIN`), so a fresh OpenCode is fetched on
every build.

`./validate.sh` requires a working Docker environment and a built image: it
lints the launcher, resolves the node active LTS from nodejs.org as a
reference, then verifies the toolchain assumptions inside the `ddr-opencode`
container (tool versions, php modules, xdebug). It fails hard if the Docker CLI
or the image is missing.

The launcher cannot run end-to-end unless the host has
`~/.local/share/opencode/auth.json` (real OpenCode login).

## How the launcher works

1. Resolves Docker binary (`DOCKER_BIN` override, then common paths).
2. Checks the image via `docker image inspect`. If absent, or if its
   `{{.Created}}` timestamp is older than 86400 seconds, or if its
   `org.opencode.docker.uid`/`org.opencode.docker.gid` labels don't match the
   current user (images without the labels are left alone), triggers a rebuild.
   Timestamp is parsed with GNU `date -d`, falling back to BSD `date -j -f`
   (nanoseconds stripped) - keep both branches working (macOS support).
3. If a rebuild is needed but no `Dockerfile` is found next to the script,
   it aborts with an error.
4. Runs `docker run --rm --init -it --user $uid:$gid --workdir <cwd>` with the
   project dir and the OpenCode data + state dirs bind-mounted, an empty
   read-only file mounted over `$project_dir/.env.local` when it exists
   (see the masking bullet above), XDG env vars
   pointing at `/home/opencode`, `OPENCODE_DISABLE_AUTOUPDATE=true`, the host
   git identity (when configured) forwarded as `GIT_AUTHOR_*`/`GIT_COMMITTER_*`,
   and `--network "$network"` (the `development` network by default, overridable
   via `OPENCODE_DOCKER_NETWORK`), passing `$OPENCODE_DOCKER_COMMAND` as the
   container command *only when set* (the acp wrapper sets it to `acp`, which
   also swaps `-it` for `-i`); with no command, the image's empty default CMD
   runs the interactive TUI.

## Conventions

- No comments in code files unless the user asks for them.
- `set -eu` POSIX sh in the launcher; `printf` over `echo`; no bash-isms.
- Keep the image free of third-party apt repos while Ubuntu ships the needed
  PHP; when PHP 8.6 is required, plan to introduce ondrej/sury for that version.
- Do not commit unless the user asks.