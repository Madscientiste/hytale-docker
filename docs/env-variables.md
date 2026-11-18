# Environment Variables

This document describes all environment variables that can be used to configure the Hytale server container, server settings, and runtime behavior.

## Table of Contents

- [Container & Permissions](#container--permissions)
- [Logging](#logging)
- [Server Download](#server-download)
- [Automatic Restarts](#automatic-restarts)
- [Health Check](#health-check)
- [Server Configuration](#server-configuration)
- [Mods](#mods)
- [Recommended Plugins](#recommended-plugins)
- [JVM & Server Startup](#jvm--server-startup)
- [Server Options](#server-options)
- [World Check and Repair](#world-check-and-repair)
- [Backup Configuration](#backup-configuration)
- [RCON Configuration](#rcon-configuration)
- [Authentication](#authentication)

---

## Container & Permissions

These variables control the container user/group permissions to match your host system, preventing permission issues with mounted volumes.

### `HOST_UID` / `HOST_GID`

**Type:** Integer  
**Default:** `HOST_UID=1000`, `HOST_GID=1000` (when not set, container uses default `hytale` user with UID/GID 1000)  
**Description:** User ID (UID) and Group ID (GID) for the `hytale` user/group inside the container. Should match your host user's UID/GID to avoid permission issues.

**How to set:**
- **Via docker-compose.yml**: Use `UID` and `GID` environment variables (converted to `HOST_UID`/`HOST_GID` inside container)
- **Directly**: Set `HOST_UID` and `HOST_GID` as container environment variables

**Example (docker-compose.yml):**
```yaml
environment:
  - HOST_UID=${UID:-1000}
  - HOST_GID=${GID:-1000}
```

`docker compose` reads `UID` and `GID` from your shell or from `.env`. Bash and zsh set `UID`, but they do not export it, so `docker compose` does not see it. Nothing sets `GID`. The simplest way is to put both in `.env`, with the numbers that `id -u` and `id -g` print:

```bash
# .env
UID=1000
GID=1000
```

**Example (command line):**
```bash
export UID          # bash refuses "export UID=$(id -u)": UID is read-only there
export GID=$(id -g)
docker compose up -d
```

**Example (direct):**
```bash
docker run -e HOST_UID=1000 -e HOST_GID=1000 ...
```

**Note:** The container runs as root initially to modify the user/group at runtime, then drops privileges to the `hytale` user before starting the server. When both are set, it also gives everything in `/data` to `HOST_UID:HOST_GID` at every start.

### `MACHINE_ID`

**Type:** String (a UUID, or 32 hex characters)  
**Default:** generated on the first start and saved to `/data/machine-id`  
**Description:** The server's hardware UUID, written to `/etc/machine-id`. The server derives the encryption key of its saved credentials (`auth.enc`) from it, so it must stay the same across restarts. Leave it unset to keep the saved `/data/machine-id`; set it only to move a server to a new data folder with the same identity.

**Example:**
```yaml
environment:
  - MACHINE_ID=0f1e2d3c4b5a69788796a5b4c3d2e1f0
```

---

## Logging

### `LOG_LEVEL`

**Type:** String  
**Default:** `INFO`  
**Description:** Controls the verbosity of log output from container scripts. Does not affect Hytale server logs.

**Valid Values:**
- `ERROR` - Only error messages
- `WARN` - Warnings and errors
- `INFO` - Informational messages, warnings, and errors (default)
- `DEBUG` - All messages including debug information

**Example:**
```bash
LOG_LEVEL=DEBUG
```

---

## Server Download

### `VERSION`

**Type:** String  
**Default:** `LATEST`  
**Description:** Hytale server version to download. The server only updates when it restarts, and only when `VERSION=LATEST`.

- `LATEST`: on start, checks for a new version and downloads it. The check runs at most once an hour (see [`FORCE_UPDATE_CHECK`](#force_update_check)).
- Any other value pins the server to that version. Nothing is checked or downloaded. An installed server of another version keeps running (the log warns); start once with `FORCE_DOWNLOAD=true` to install the pinned one.

**Valid Values:**
- `LATEST` - Downloads the latest version from the manifest (default)
- A numbered version, the format Hytale uses since 2026 (e.g., `0.7.7`)
- A date version with hash, the format used until early 2026 (e.g., `2026.01.17-4b0f30090`)

A date without the hash (e.g., `2026.01.17`) is not supported and stops the container with an error.

**Examples:**
```bash
# Download latest version (default)
VERSION=LATEST

# Pin a specific version
VERSION=0.7.7
```

**Error Handling:** when the version is downloaded (no server installed yet, or `FORCE_DOWNLOAD=true`):
- If a partial version (date without hash) is specified, the container will exit with an error message
- If a non-existent version is specified, the container will exit with a 404 error message

---

### `PATCHLINE`

**Type:** String  
**Default:** `release`  
**Description:** Patchline/branch to download from. Typically `release` for stable versions.

**Example:**
```bash
PATCHLINE=release
```

---

### `FORCE_DOWNLOAD`

**Type:** Boolean  
**Default:** `false`  
**Description:** Force re-download of server files even if they already exist.

**Valid Values:**
- `true` - Always download
- `false` - Skip download if files exist (default)

**Example:**
```bash
FORCE_DOWNLOAD=true
```

---

### `FORCE_UPDATE_CHECK`

**Type:** Boolean  
**Default:** `false`  
**Description:** Force update checking regardless of cooldown period. Only applies when `VERSION=LATEST`.

**Valid Values:**
- `true` - Force update check (bypasses 1-hour cooldown)
- `false` - Respect 1-hour cooldown between update checks (default)

**Usage:**
- Useful when you want to immediately check for updates without waiting for cooldown
- Only affects update checking when `VERSION=LATEST`
- Has no effect when using specific versions

**Example:**
```yaml
# docker-compose.yml (then: docker compose up -d)
environment:
  - FORCE_UPDATE_CHECK=true
```

To check once without changing settings, use `docker exec hytale hy-restart --now`: a restart from `hy-restart` always skips the cooldown. A variable typed on the host (`FORCE_UPDATE_CHECK=true docker restart ...`) does not reach the container.

**Note:** This only forces the **check** for updates. If no new version is available, no download will occur.

---

## Automatic Restarts

Off by default. See [Update Management](update-management.md#restarting-the-server) for `hy-restart` and how restarts apply updates.

### `RESTART_MODE`

**Type:** String  
**Default:** `off`  
**Valid Values:**
- `off` - No automatic restarts; restart by hand with `docker exec hytale hy-restart`
- `schedule` - Restart every day at `RESTART_TIME`
- `on-update` - Restart when a new server version is available (only with `VERSION=LATEST`), checked every `RESTART_CHECK_MINUTES`

### `RESTART_TIME`

**Type:** String (`HH:MM`, 24-hour)  
**Default:** `04:00`  
**Description:** Time of the daily restart with `RESTART_MODE=schedule`, in the container time zone (`TZ`). The player warning starts at this time; the restart follows `RESTART_WARN_MINUTES` later.

### `RESTART_WARN_MINUTES`

**Type:** Integer  
**Default:** `5`  
**Description:** How long players are warned before a restart (`hy-restart` and automatic restarts). `0` restarts without warning. Warnings use RCON (on by default); with RCON off or only `RCON_PASSWORD_HASH`, there are none.

### `RESTART_CHECK_MINUTES`

**Type:** Integer (minimum `10`)  
**Default:** `60`  
**Description:** How often `RESTART_MODE=on-update` checks for a new version.

### `RESTART_REASON`

**Type:** String  
**Default:** empty  
**Description:** A reason that `hy-restart` adds to each player warning when it is run without `--reason`. Set it for one call: `docker exec -e RESTART_REASON="new mods" hytale hy-restart`.

### `TZ`

**Type:** String (time zone name, e.g. `Europe/Paris`)  
**Default:** `UTC`  
**Description:** Container time zone, used by `RESTART_TIME` and log timestamps.

---

## Health Check

The image has a Docker health check (`hy-health.sh`), shown as `healthy` / `unhealthy` in `docker ps`:

- **Starting** (login, configuration, plugins): healthy for up to `HEALTH_STARTUP_MINUTES`, then unhealthy. The server download and the [world check](#world-check-and-repair) do not count: they are always healthy, and the clock starts again after them. A long startup usually means the container waits for a browser login; see the logs.
- **Running**: healthy while the server process runs and answers the `who` command over RCON within [`RCON_COMMAND_TIMEOUT`](#rcon_command_timeout) seconds (default `10`). No reply, or a reply starting with `Error:`, counts as unhealthy. Without RCON (or with only `RCON_PASSWORD_HASH`) only the process is checked. The first 5 minutes after the server starts always count as healthy.

### `HEALTH_STARTUP_MINUTES`

**Type:** Integer  
**Default:** `15`  
**Description:** How long startup may take before the container reports unhealthy.

---

## Server Configuration

These variables configure the Hytale server's `config.json` file. All settings are optional and will only be applied if the variable is set. The configuration step runs automatically during container startup (step 3 of the entrypoint).

The `docker-compose.yml` of this repository always sets `SERVER_NAME`, `MOTD`, `MAX_PLAYERS`, `MAX_VIEW_RADIUS`, `DEFAULT_WORLD` and `DEFAULT_GAME_MODE`. So if you edit those keys in `config.json` by hand, the next start overwrites them. Change the variables instead.

Each default below shows two values: the `docker-compose.yml` default, and the image default when the variable is unset (the value in a new `config.json`).

### `SERVER_NAME`

**Type:** String  
**Default:** `My Hytale Server` in `docker-compose.yml` (`Hytale Server` when unset)  
**Description:** Name of the server displayed to players.

**Example:**
```bash
SERVER_NAME="My Awesome Server"
```

---

### `MOTD`

**Type:** String  
**Default:** `Welcome to our Hytale server!` in `docker-compose.yml` (empty when unset)  
**Description:** Message of the Day displayed to players.

**Example:**
```bash
MOTD="Welcome to our server!"
```

---

### `SERVER_PASSWORD`

**Type:** String  
**Default:** `""` (empty, no password)  
**Description:** Server password. Leave empty for public server.

**Example:**
```bash
SERVER_PASSWORD="mySecurePassword123"
```

**Security Note:** Consider using Docker secrets or environment files for sensitive passwords.

---

### `MAX_PLAYERS`

**Type:** Integer  
**Default:** `50` in `docker-compose.yml` (`100` when unset)  
**Description:** Maximum number of players allowed on the server simultaneously.

**Example:**
```bash
MAX_PLAYERS=50
```

---

### `MAX_VIEW_RADIUS`

**Type:** Integer  
**Default:** `32`  
**Description:** Maximum view radius for players (chunks).

**Example:**
```bash
MAX_VIEW_RADIUS=64
```

---

### `DEFAULT_WORLD`

**Type:** String  
**Default:** `"default"`  
**Description:** Default world name to load.

**Example:**
```bash
DEFAULT_WORLD="my_custom_world"
```

---

### `DEFAULT_GAME_MODE`

**Type:** String  
**Default:** `"Adventure"`  
**Description:** Default game mode for new players.

**Valid Values:**
- `Adventure`
- `Creative`
- `Survival`

**Example:**
```bash
DEFAULT_GAME_MODE="Creative"
```

---

## Mods

Hytale loads every `.jar` and `.zip` in `/data/mods` (on the host: `data/mods`). Copy mods there yourself, or list download links in `MODS`. To load mods from more folders, see [`EXTRA_MODS_DIRS`](#extra_mods_dirs).

### `MODS`

**Type:** String (download links, separated by commas, spaces or new lines)  
**Default:** empty  
**Description:** Mods to download at startup. Each link must end in the mod's `.jar` or `.zip` file name.

- A mod is downloaded once. When its file is already in `/data/mods`, it is kept as is (no download).
- Files are never deleted. Mods you add by hand are not touched. When you remove a link from `MODS`, its file stays and the logs warn on every start until you delete it.
- To update a mod, replace its link with the new version's link, then delete the old file from `data/mods`.
- If a listed mod cannot be downloaded, the container stops instead of starting without it (worlds may depend on it).

**Example:**
```bash
MODS=https://example.com/mods/cool-mod-1.2.0.jar,https://example.com/mods/other-mod.zip
```

---

## Recommended Plugins

Hytale's official server manual recommends four plugins. This image installs them by default. On every start it checks for the build that matches the installed server version in each plugin's GitHub releases, and downloads it into `/data/mods` when it is missing. Each download is checked against the sha256 checksum GitHub records for the file; a file that does not match is not installed. When GitHub has no checksum for a file, it is installed without a check, and the log warns.

| Setting | Plugin | What it does |
|---|---|---|
| `ENABLE_WEBSERVER` | [Nitrado:WebServer](https://github.com/nitrado/hytale-plugin-webserver) | Web server (HTTPS) that the next two plugins use |
| `ENABLE_QUERY` | [Nitrado:Query](https://github.com/nitrado/hytale-plugin-query) | Server info and player count over HTTP |
| `ENABLE_METRICS` | [ApexHosting:PrometheusExporter](https://github.com/apexhosting/hytale-plugin-prometheus) | Prometheus metrics |
| `ENABLE_PERFORMANCE_SAVER` | [Nitrado:PerformanceSaver](https://github.com/nitrado/hytale-plugin-performance-saver) | Lowers load under pressure |

All four are **Type:** Boolean, **Default:** `true`. Set one to `false` to turn that plugin off.

- `ENABLE_QUERY` and `ENABLE_METRICS` need `ENABLE_WEBSERVER=true`.
- A plugin you turn off is moved to `/data/.disabled-plugins`, outside `mods/`, so the server ignores it. Turning it back on moves it back.
- When the server version changes, the image replaces the jars it installed with the builds for the new version. If a plugin has no build for that version yet, it is skipped for now (with a warning) and the server starts without it.
- If you put your own copy of one of these plugins in `data/mods`, the image leaves that plugin alone.
- The image only touches the jars it downloaded itself. They are listed in `data/.recommended-plugins.txt`.

**Web server port:** the web server listens on the game port + 3, so **5523/tcp** by default, with a self-signed certificate. It is not reachable from outside the container until you map the port in `docker-compose.yml` (`"5523:5523/tcp"`). Requests need a login: a player, or a service account. To make basic server info public, add it to the `ANONYMOUS` group in `permissions.json`. See the plugins' READMEs (linked above) for service accounts and permissions.

**PerformanceSaver:** caps the server at 20 ticks per second (5 when nobody is online), lowers the view radius while CPU or memory is under pressure, and raises it again when they recover. Set `ENABLE_PERFORMANCE_SAVER=false` to keep the server's own behaviour.

**Example:**
```bash
ENABLE_METRICS=false             # no Prometheus metrics
ENABLE_PERFORMANCE_SAVER=false   # keep the full tick rate and view radius
```

---

## JVM & Server Startup

### `INIT_MEMORY`

**Type:** String (Memory size)  
**Default:** `8G` in `docker-compose.yml` (`12G` when unset)  
**Description:** Initial Java heap size (JVM `-Xms` option).

**Format:** Use standard JVM memory format (e.g., `512M`, `2G`, `4096M`)

**Example:**
```bash
INIT_MEMORY=8G
```

---

### `MAX_MEMORY`

**Type:** String (Memory size)  
**Default:** `16G` in `docker-compose.yml` (`12G` when unset)  
**Description:** Maximum Java heap size (JVM `-Xmx` option).

**Format:** Use standard JVM memory format (e.g., `512M`, `2G`, `4096M`)

**Example:**
```bash
MAX_MEMORY=16G
```

**Note:** Should be equal to or greater than `INIT_MEMORY`.

---

### `JVM_OPTS`

**Type:** String  
**Default:** `""` (empty)  
**Description:** Additional JVM options to append to the base JVM arguments. Java uses the last value of an option, so `JVM_OPTS` can also change a default of the image.

**Example:**
```bash
JVM_OPTS="-Dsome.property=value -XX:MaxGCPauseMillis=100"
```

---

### `JVM_XX_OPTS`

**Type:** String  
**Default:** `""` (empty)  
**Description:** Additional JVM `-XX:` options to prepend to the base JVM arguments. The image's own options come later and win, so `JVM_XX_OPTS` cannot change a default: use `JVM_OPTS` for that. The garbage collector is G1 (`-XX:+UseG1GC`); adding another one, such as `-XX:+UseZGC`, stops Java with "Multiple garbage collectors selected".

**Example:**
```bash
JVM_XX_OPTS="-XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/data"
```

---

### `BIND_ADDRESS`

**Type:** String (IP address)  
**Default:** Not set (uses server default)  
**Description:** IP address to bind the server to. Leave unset to bind to all interfaces.

**Example:**
```bash
BIND_ADDRESS="0.0.0.0"
```

---

### `TRANSPORT_TYPE`

**Type:** String  
**Default:** Not set (uses server default)  
**Description:** Transport type for server connections.

**Example:**
```bash
TRANSPORT_TYPE="quic"
```

---

### `AUTH_MODE`

**Type:** String: `authenticated`, `offline` or `insecure`  
**Default:** Not set (the server uses `authenticated`)  
**Description:** Authentication mode for the server. Another value stops the container with an error.

**Example:**
```bash
AUTH_MODE=offline
```

---

## Server Options

More options of the Hytale server. Each one is left out when empty, so the server's own default applies. A wrong value stops the container with an error that names the setting.

### `BOOT_COMMANDS`

**Type:** String (console commands, separated by `;` or new lines)  
**Default:** empty  
**Description:** Console commands the server runs at every start, in order, as if typed in the console.

- Write commands without the leading `/`.
- A command cannot contain a comma: the server splits its values on commas.

**Example:**
```bash
BOOT_COMMANDS=say Server restarted; weather clear
```

---

### `SERVER_LOG`

**Type:** String  
**Default:** empty (the server's levels)  
**Description:** Log levels of the server itself (`--log`). `LOG_LEVEL` only covers this image's scripts.

Give a level for all logs, or `Logger:LEVEL` items, separated by commas and without spaces. Levels: `SEVERE`, `WARNING`, `INFO`, `CONFIG`, `FINE`, `FINER`, `FINEST`, `ALL`, `OFF`.

**Example:**
```bash
SERVER_LOG=WARNING
```

---

### `DISABLE_SENTRY`

**Type:** Boolean  
**Default:** `false`  
**Description:** `true` stops the server from sending crash reports to Hytale (Sentry).

---

### `IGNORE_BROKEN_MODS`

**Type:** Boolean  
**Default:** `false`  
**Description:** `true` lets the server start even when a mod fails to load. That mod is then missing, so check the logs.

---

### `UNIVERSE_DIR`

**Type:** String (absolute path inside the container)  
**Default:** empty (`/data/universe`)  
**Description:** The folder that holds the worlds and player data. It is created when missing. Keep it on a volume, or the worlds are lost with the container.

**Example:**
```bash
UNIVERSE_DIR=/worlds
```

---

### `EXTRA_MODS_DIRS`

**Type:** String (absolute paths inside the container, separated by `;`)  
**Default:** empty  
**Description:** More folders the server loads mods from, besides `/data/mods`. Missing folders are created. `MODS` downloads still go to `/data/mods`.

**Example:**
```bash
EXTRA_MODS_DIRS=/mods/shared;/mods/testing
```

---

### `SERVER_ARGS`

**Type:** String (server options, separated by spaces)  
**Default:** empty  
**Description:** Any other server option, added at the end of the command line. Run `docker compose exec hytale java -jar /data/HytaleServer.jar --help` to list them.

- Values are split on spaces, so a value cannot contain one. Use a setting above when there is one.
- Do not put login tokens here: every user on the host can read the command line. The image already passes them safely.
- It is not checked, and it is not used for the world check below.

**Example:**
```bash
SERVER_ARGS=--disable-file-watcher
```

---

## World Check and Repair

The server can check every world, and repair broken chunks. The image runs this check before the server starts; the server then starts as usual. If the check fails, the server is not started and the container stops.

The check runs at every start (also on `hy-restart`), and a large world makes startup slower. Turn it on, start once, then turn it off. While it runs, the health check reports `healthy`.

### `VERIFY_WORLDS`

**Type:** Boolean  
**Default:** `false`  
**Description:** `true` checks every world before the server starts.

### `RECOVERY_MODE`

**Type:** String: `REGENERATE` or `FROM_BACKUP_OR_REGENERATE`  
**Default:** empty (check only, no repair)  
**Description:** What the check does with a broken chunk. It only works with `VERIFY_WORLDS=true`.

- `REGENERATE`: makes the chunk again from the world generator. What players built there is lost.
- `FROM_BACKUP_OR_REGENERATE`: takes the chunk from the newest backup in `BACKUP_DIR` that has it, else makes it again. It needs `ENABLE_BACKUPS=true`, so the server knows where the backups are. The server may answer that its world storage cannot do this; then restore a backup instead.

Make a copy of `data/universe` first: a repair changes the world.

**Example (one start, then remove both lines):**
```bash
VERIFY_WORLDS=true
RECOVERY_MODE=REGENERATE
```

---

## Backup Configuration

These variables control the Hytale server's automatic backup functionality. Backups are enabled by default.

### `ENABLE_BACKUPS`

**Type:** Boolean  
**Default:** `true`  
**Description:** Enable or disable automatic server backups.

**Valid Values:**
- `true` - Enable backups (default)
- `false` - Disable backups

**Example:**
```bash
ENABLE_BACKUPS=true
```

**Example (disable backups):**
```bash
ENABLE_BACKUPS=false
```

---

### `BACKUP_DIR`

**Type:** String (Absolute path)  
**Default:** `/data/backups`  
**Description:** Absolute directory path where backups are stored. Must be an absolute path starting with `/` (e.g., `/backup`, `/data/backups`). This allows mounting volumes at specific paths.

**Requirements:**
- Must be an absolute path (starting with `/`)
- The directory will be created by the server if it doesn't exist

**Example:**
```bash
BACKUP_DIR=/data/backups
```

**Example (using mounted volume):**
```bash
BACKUP_DIR=/backup
```

---

### `BACKUP_FREQUENCY`

**Type:** Integer  
**Default:** `30`  
**Description:** Backup interval in minutes. The server will create a backup at this interval.

**Example:**
```bash
BACKUP_FREQUENCY=30
```

**Example (backup every hour):**
```bash
BACKUP_FREQUENCY=60
```

---

### `BACKUP_MAX_COUNT`

**Type:** Integer  
**Default:** `5`  
**Description:** Maximum number of backups to keep. When this limit is reached, the oldest backup will be deleted when a new backup is created.

**Example:**
```bash
BACKUP_MAX_COUNT=5
```

**Example (keep 10 backups):**
```bash
BACKUP_MAX_COUNT=10
```

---

## RCON Configuration

These variables control the RCON (Remote Console) plugin, which provides remote console access to your Hytale server using the standard RCON protocol.

### `RCON_ENABLED`

**Type:** Boolean  
**Default:** `true`  
**Description:** Enable or disable the RCON plugin. When disabled, the plugin will not be downloaded or configured, and an installed RCON plugin is moved from `/data/mods` to `/data/.disabled-plugins`.

**Valid Values:**
- `true` - Enable RCON plugin (default)
- `false` - Disable RCON plugin

**Example:**
```bash
RCON_ENABLED=true
```

---

### `RCON_VERSION`

**Type:** String  
**Default:** empty  
**Description:** Which RCON plugin to install.

- empty (default): the release this image was tested with. Its sha256 checksum is checked; a file that does not match is refused.
- `latest`: the newest release on GitHub, not checked. If GitHub cannot be reached, the installed version is kept.
- A release tag such as `rcon-v1.1.0`, or just `1.1.0`: that release, 1.1.0 or newer. A value that starts with a digit or `v` becomes `rcon-v<version>`, so 1.0.0 (tag `v1.0.0`) cannot be chosen. Only the tested release (`rcon-v1.2.0`) is checked.

Other versions found in `/data/mods` are moved to `/data/.disabled-plugins`, so only one RCON plugin loads.

---

### `RCON_HOST`

**Type:** String (IP address)  
**Default:** `0.0.0.0` in `docker-compose.yml` (`127.0.0.1` when unset)  
**Description:** The address the plugin listens on **inside** the container.

- `0.0.0.0`: needed for a published port to work. Who can connect is decided by the port line in `docker-compose.yml`, which is `127.0.0.1:25575:25575` (this host only).
- `127.0.0.1`: only programs inside the container can connect (`docker compose exec hytale rcon-cli`).

RCON is not encrypted, and Docker's published ports bypass firewalls such as ufw: never publish it on all interfaces (`25575:25575`). See [rcon.md](rcon.md#who-can-connect).

With `0.0.0.0`, plugin 1.2.0 logs a warning at every start ("RCON is listening on 0.0.0.0, which is not a loopback address"). In Docker this is expected: the port line keeps RCON on this host.

---

### `RCON_PORT`

**Type:** Integer, 1 to 65535  
**Default:** `25575`  
**Description:** Port number for the RCON server to listen on.

---

### `RCON_PASSWORD`

**Type:** String  
**Default:** empty  
**Description:** Your RCON password. Empty: the image makes a random password once and saves it in `/data/.rcon-password` (mode 600). `rcon-cli` inside the container, the restart warnings and the health check use it by themselves.

The image hashes the password from stdin, so it never appears on a command line. The old example value `verysecurepassword` logs a warning.

`RCON_PASSWORD` may also be a hash from `gen-psswd`. The image then gives it to the plugin as it is, and it works like `RCON_PASSWORD_HASH` alone (same limits, see below).

**Example:**
```bash
RCON_PASSWORD=MySecurePassword123
```

---

### `RCON_PASSWORD_HASH`

**Type:** String  
**Default:** empty  
**Description:** A password hash, made with `docker compose exec hytale gen-psswd`. It wins over `RCON_PASSWORD` for the plugin. With a hash only, the image cannot log in itself: no restart warnings over RCON, and a process-only health check.

Two formats:

- `pbkdf2-sha512:210000:<salt>:<hash>`: the default from `gen-psswd`. Needs plugin 1.2.0 or newer.
- `<salt>:<hash>`: the old, fast format, from `gen-psswd --old`. Plugins before 1.2.0 know only this one. Plugin 1.2.0 still accepts it, but warns at every start.

If you set both `RCON_PASSWORD` and `RCON_PASSWORD_HASH`, they must match. The container refuses to start when they don't: otherwise `rcon-cli`, the restart warnings and the health check would log in with the wrong password.

---

### `RCON_MAX_CONNECTIONS`

**Type:** Integer, 1 to 1000  
**Default:** `10`  
**Description:** Maximum number of concurrent RCON connections allowed.

**Example:**
```bash
RCON_MAX_CONNECTIONS=10
```

---

### `RCON_MAX_FRAME_SIZE`

**Type:** Integer, 64 to 1048576  
**Default:** `4096`  
**Description:** Maximum RCON frame size in bytes.

**Example:**
```bash
RCON_MAX_FRAME_SIZE=4096
```

---

### `RCON_READ_TIMEOUT_MS`

**Type:** Integer, 1 to 300000  
**Default:** `30000`  
**Description:** Read timeout for RCON connections in milliseconds.

**Example:**
```bash
RCON_READ_TIMEOUT_MS=30000
```

---

### `RCON_CONNECTION_TIMEOUT_MS`

**Type:** Integer, 1 to 60000  
**Default:** `5000`  
**Description:** Connection timeout for RCON connections in milliseconds.

**Example:**
```bash
RCON_CONNECTION_TIMEOUT_MS=5000
```

---

The ranges above are the RCON plugin's own. A number outside its range stops the container with an error that names the variable: the plugin would refuse the whole config, and RCON would stay off. With an `RCON_VERSION` older than 1.2.0, only whole numbers are checked.

---

### `RCON_COMMAND_TIMEOUT`

**Type:** Integer (seconds)  
**Default:** `10`  
**Description:** How long the health check and the restart warnings wait for the server to answer an RCON command. Keep it below the health check's 15-second timeout. It is not in `docker-compose.yml`: add it to the `environment` list to use it.

---

### `rcon-cli` inside the container

`docker compose exec hytale rcon-cli <command>` connects to the server's RCON and uses `RCON_PASSWORD` or the generated password, with no flags. See [rcon.md](rcon.md).

---

## Authentication

Authentication is handled automatically via `hy-auth.sh` during container startup. Credentials are stored in `/data/auth.json`.

### `AUTH_REFRESH_HOURS`

**Type:** Integer (hours, minimum `1`)  
**Default:** `24`  
**Description:** How often the login is refreshed in the background while the server runs. Hytale's refresh token expires after 30 days without use, so keep this well below 720.

### Not used: token variables

> **Note:** The variables below are **not currently used** - authentication tokens are read from `/data/auth.json`, not environment variables. They are documented for reference only.

### `SESSION_TOKEN`

**Type:** String  
**Source:** Read from `/data/auth.json` (not environment)  
**Description:** Hytale session token for server authentication.

---

### `IDENTITY_TOKEN`

**Type:** String  
**Source:** Read from `/data/auth.json` (not environment)  
**Description:** Hytale identity token for server authentication.

---

### `OWNER_UUID`

**Type:** String (UUID)  
**Source:** Read from `/data/auth.json` (not environment)  
**Description:** UUID of the server owner/account.

---

### `OWNER_NAME`

**Type:** String  
**Source:** Read from `/data/auth.json` (not environment)  
**Description:** Username of the server owner/account.

---

## Usage Examples

### Basic docker-compose.yml

```yaml
services:
  hytale:
    build: .
    environment:
      - HOST_UID=${UID:-1000}
      - HOST_GID=${GID:-1000}
      - SERVER_NAME=My Server
      - MAX_PLAYERS=50
      - INIT_MEMORY=8G
      - MAX_MEMORY=16G
    volumes:
      - "./data:/data"
    ports:
      - "5520:5520/udp"
```

### Using .env file

Create a `.env` file in your project root:

```bash
# Container permissions (the numbers id -u and id -g print)
UID=1000
GID=1000

# Server configuration
SERVER_NAME=My Awesome Server
MOTD=Welcome!
MAX_PLAYERS=50
DEFAULT_GAME_MODE=Creative

# JVM settings
INIT_MEMORY=8G
MAX_MEMORY=16G

# Backup configuration
ENABLE_BACKUPS=true
BACKUP_DIR=/data/backups
BACKUP_FREQUENCY=30
BACKUP_MAX_COUNT=5

# Logging
LOG_LEVEL=INFO
```

Then reference in docker-compose.yml:
```yaml
environment:
  - HOST_UID=${UID:-1000}
  - HOST_GID=${GID:-1000}
  - SERVER_NAME=${SERVER_NAME:-My Hytale Server}
  - MAX_PLAYERS=${MAX_PLAYERS:-50}
```

### Command line

```bash
docker run -e HOST_UID=1000 -e HOST_GID=1000 \
  -e SERVER_NAME="My Server" \
  -e MAX_PLAYERS=50 \
  -e INIT_MEMORY=8G -e MAX_MEMORY=16G \
  -e BACKUP_DIR=/backup \
  -e BACKUP_FREQUENCY=60 \
  -v ./data:/data \
  -v ./backups:/backup \
  -p 5520:5520/udp \
  hytale-server
```

### Disable backups

```bash
ENABLE_BACKUPS=false
```

---

## Notes

- All environment variables are optional unless otherwise specified
- Default values are applied when variables are not set
- **Container permissions** (`HOST_UID`/`HOST_GID`) are applied at container startup via the entrypoint wrapper
- **Server download** is handled by `hy-downloader.sh` utility script
- **Configuration** step runs automatically during container startup (step 3) and updates `config.json` based on environment variables
- **Authentication** is handled automatically via `hy-auth.sh` - credentials are stored in `/data/auth.json`, not environment variables
- **JVM settings** and **server startup options** are applied when the server starts

