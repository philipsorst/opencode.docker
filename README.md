# opencode.docker

Run the [OpenCode](https://opencode.ai) AI agent inside a sandboxed,
general-purpose dev container. A single launcher builds the image when needed,
keeps it fresh, and starts the OpenCode ACP server against your project
directory.

## What you get

The `ddr-opencode` image is based on Ubuntu 26.04 LTS and ships a
general-purpose toolchain:

- **OpenJDK 25** (LTS)
- **PHP 8.5** with `curl`, `mbstring`, `xml`, `zip`, `intl`, `sqlite3`,
  `bcmath`, `gd`, and **Xdebug** (passive by default)
- **Composer** 2.x
- CLI tools: `git`, `curl`, `ripgrep`, `openssh-client`, `unzip`, `zip`, `bash`

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
2. Rebuild it automatically if the image is older than one day, then
   `docker run`s the OpenCode **ACP** server with your project as the working
   directory.

Your project directory is mounted read-write and the container runs as your
own UID/GID, so files created by the agent belong to you. The container reuses
your host OpenCode credentials instead of requiring a separate login, and your
OpenCode state (`sessions`, history) is persisted in
`$XDG_STATE_HOME/opencode` (`~/.local/state/opencode` by default) so sessions
survive between runs. Config and cache stay inside the container and are
discarded on each run.

## Configuration

Environment variables (all optional):

| Variable | Default | Purpose |
| --- | --- | --- |
| `OPENCODE_DOCKER_IMAGE` | `ddr-opencode` | Image name to build/run |
| `DOCKER_BIN` | auto-detected | Absolute path to the Docker CLI |
| `XDG_DATA_HOME` | `$HOME/.local/share` | Host "opencode" data dir to share |
| `XDG_STATE_HOME` | `$HOME/.local/state` | Host "opencode" state dir to share (sessions/history) |

## Extending the image

Add packages in the stable layer of the `Dockerfile` (the `apt-get install`
block) — they are cached and only reinstalled when the base image updates.
Installs that must track fast-moving upstream releases (like OpenCode itself)
belong in the volatile layer below `ARG CACHEBUST`.

## Verification

```sh
sh -n opencode-acp-docker                              # lint the launcher
docker build --pull -t ddr-opencode \
  --build-arg "CACHEBUST=$(date +%s)" .                # build the image
docker run --rm --entrypoint bash ddr-opencode -c 'java -version; php -v; composer --version'
```