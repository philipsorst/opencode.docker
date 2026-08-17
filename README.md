# opencode.docker

Run the [OpenCode](https://opencode.ai) AI agent inside a sandboxed,
general-purpose dev container. A single launcher builds the image when needed,
keeps it fresh, and starts the OpenCode ACP server against your project
directory.

## What you get

The `ddr-opencode` image is based on Ubuntu 26.04 LTS and ships a
general-purpose toolchain:

- **OpenJDK 25** (LTS)
- **Node.js** (current active LTS, resolved at build time)
- **Python 3.14** (the Ubuntu 26.04 default `python3`, security-maintained).
  The system interpreter is PEP 668-protected: install packages with `uv`
  or in a `venv`, not globally.
- **PHP 8.5** with `curl`, `mbstring`, `xml`, `zip`, `intl`, `sqlite3`,
  `pgsql`/`pdo_pgsql`, `bcmath`, `gd`, and **Xdebug** (passive by default)
- **Composer** 2.x
- **uv** (Python package manager) with its `uvx` companion
- **project-docs-mcp** — RAG docs-search MCP server (`search_project_docs`),
  installed globally via npm; needs `OPENROUTER_API_KEY` at runtime
- CLI tools: `git`, `git-lfs`, `jq`, `curl`, `ripgrep`, `openssh-client`,
  `unzip`, `zip`, `bash`
- Native build toolchain: `build-essential` (gcc/g++/make), `cmake`,
  `pkg-config`, `file`, `rsync`, `tree`
- Data tooling: `postgresql-client` (psql), `sqlite3`, `shellcheck`, and the
  network debuggers `iputils-ping`, `dnsutils` (dig), `netcat-openbsd`

The container runs with a UTF-8 locale (`LANG`/`LC_ALL=C.UTF-8`). `/home/opencode`
is seeded with a minimal `.gitconfig` (`init.defaultBranch=main`,
`safe.directory = *`, and a generic commit identity), so agents can clone and
commit without setup. If the host has a git identity (`git config user.name`/
`user.email`), the launcher instead forwards it as `GIT_AUTHOR_*`/`GIT_COMMITTER_*`
environment variables — env overrides config, so container commits carry your
name/email; the generic identity is the fallback.

No third-party package repositories are used while Ubuntu ships the current
PHP; the plan is to move PHP to the ondrej/sury repositories when a PHP 8.6
release requires it.

## Requirements

- Docker (with BuildKit support)
- An existing OpenCode login on the host:
  `$XDG_DATA_HOME/opencode/auth.json`
  (default `~/.local/share/opencode/auth.json`) — run `opencode auth` once if
  you don't have one yet.

## Usage

```sh
cd /path/to/your/project
/path/to/opencode.docker/opencode-acp-docker
```

The launcher will:

1. Check for the `ddr-opencode` image and build it if it does not exist.
2. Rebuild it automatically if the image is older than one day, or was built
   for a different user ID (so `$HOME` stays writable for your account), then
   `docker run`s the OpenCode **ACP** server with your project as the working
   directory.

Your project directory is mounted read-write and the container runs as your
own UID/GID, so files created by the agent belong to you. The container reuses
your host OpenCode credentials instead of requiring a separate login, and your
OpenCode state (`sessions`, history) is persisted in
`$XDG_STATE_HOME/opencode` (`~/.local/state/opencode` by default) so sessions
survive between runs. Config and cache stay inside the container and are
discarded on each run — except for an optional Docker-specific config, below.

### Docker-specific configuration

If you want the sandbox to use different OpenCode settings than your host, put
them in `opencode.docker.json` in your host config directory, next to your
regular `opencode.json`:

```
$XDG_CONFIG_HOME/opencode/opencode.docker.json
(~/.config/opencode/opencode.docker.json by default)
```

When that file exists, the launcher bind-mounts it **read-only** into the
container as `opencode.json`, so the agent runs with your Docker-specific
settings. Your real `opencode.json` is never mounted — the host config stays
private and only this deliberately-named file is shared. If it doesn't exist,
the container's config is ephemeral as usual.

## Configuration

Environment variables (all optional):

| Variable | Default | Purpose |
| --- | --- | --- |
| `OPENCODE_DOCKER_IMAGE` | `ddr-opencode` | Image name to build/run |
| `OPENCODE_DOCKER_NETWORK` | `development` | Docker network the container joins at run time |
| `DOCKER_BIN` | auto-detected | Absolute path to the Docker CLI |
| `XDG_DATA_HOME` | `$HOME/.local/share` | Host "opencode" data dir to share |
| `XDG_STATE_HOME` | `$HOME/.local/state` | Host "opencode" state dir to share (sessions/history) |
| `XDG_CONFIG_HOME` | `$HOME/.config` | Host "opencode" dir scanned for `opencode.docker.json` |

## Sharing host caches

To keep package installs fast across runs, the launcher auto-discovers host
cache directories from the environment and bind-mounts them read-write into the
container at the locations the tools expect (aligned with the container's
`HOME` and XDG variables, so no extra config is needed inside).

For each tool, the host dir is taken from the tool's own environment variable
when set (`UV_CACHE_DIR`, `PIP_CACHE_DIR`, `NPM_CONFIG_CACHE`,
`YARN_CACHE_FOLDER`, `COMPOSER_CACHE_DIR`, `GRADLE_USER_HOME`, `CARGO_HOME`,
`GOMODCACHE`, `NUGET_PACKAGES`, `PUB_CACHE`, `HF_HOME`), otherwise from the
XDG-aware default under `$XDG_CACHE_HOME`/`$XDG_DATA_HOME` or `$HOME`.
Explicitly configured dirs are created if missing; default paths are only
mounted when they already exist. The launcher prints a summary of what was
mounted. Covered tools: uv, pip, composer, yarn, huggingface, npm, gradle,
maven, cargo, go, nuget, pub, and both pnpm store layouts.

Mounts are read-write, so the container can mutate these directories — same
trust model as the project and state mounts.

## Reaching your stack's services

By default the container joins the `development` Docker network, so the agent
can run tests directly against sibling services (e.g. a compose Postgres) using
their compose service name instead of `localhost` — for example
`pgsql://user:password@postgres/database`. The container still does not have
access to your host shell or files outside the mounted project. If your stack
uses a different network name, set `OPENCODE_DOCKER_NETWORK` to it.

## Extending the image

Add packages in the stable layer of the `Dockerfile` (the `apt-get install`
block) — they are cached and only reinstalled when the base image updates. The
apt step uses BuildKit cache mounts (`/var/cache/apt` and `/var/lib/apt/lists`)
so adding a package re-downloads only the new/changed `.deb` files, not the
whole set. Installs that must track fast-moving upstream releases (OpenCode)
belong in the volatile layer below `ARG CACHEBUST`; Node.js and uv live in
their own unpinned layers that re-resolve their latest versions whenever the
stable layer changes, without re-running on every rebuild. See `AGENTS.md` for
the details and the `docker-clean` gotcha that keeps this caching working.

## Verification

```sh
sh -n opencode-acp-docker                              # lint the launcher
./build.sh                                             # build the image
./validate.sh                                          # validate toolchain in the container
```

`./build.sh` and the launcher build the image with `--build-arg OPENCODE_UID=$(id -u)
--build-arg OPENCODE_GID=$(id -g)`, so the container user matches your host
user; you only need the `CACHEBUST` argument when building by hand.

`./validate.sh` requires a working Docker environment and a built `ddr-opencode`
image: it fails if either is missing, then verifies the toolchain assumptions
(java, php, composer, node, python3, pip3, uv, uvx, pnpm, opencode,
project-docs-mcp, php modules, and xdebug) inside the container.
