# Environment Variables

This document describes all environment variables that can be used to configure the Hytale server container, server settings, and runtime behavior.

## Table of Contents

- [Container & Permissions](#container--permissions)
- [Logging](#logging)
- [Server Download](#server-download)
- [Server Configuration](#server-configuration)
- [JVM & Server Startup](#jvm--server-startup)
- [Backup Configuration](#backup-configuration)
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
  - HOST_GID=${GID:-1001}  # Note: 1001 is just an example - use your actual host GID
```

**Example (command line):**
```bash
export UID=$(id -u)
export GID=$(id -g)
docker compose up
```

**Example (direct):**
```bash
docker run -e HOST_UID=1000 -e HOST_GID=1000 ...
```

**Note:** The container runs as root initially to modify the user/group at runtime, then drops privileges to the `hytale` user before starting the server.

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
**Description:** Hytale server version to download. Can be `LATEST` (downloads the latest available version) or a specific version string with hash (e.g., `2026.01.17-4b0f30090`).

**Valid Values:**
- `LATEST` - Downloads the latest version from the manifest (default)
- `YYYY.MM.DD-hash` - Downloads a specific version (e.g., `2026.01.17-4b0f30090`)

**Version Format:**
- Full version format: `YYYY.MM.DD-{hash}` where:
  - `YYYY.MM.DD` is the date (e.g., `2026.01.17`)
  - `{hash}` is the version hash (e.g., `4b0f30090`)
- Partial versions (date only, without hash) are not supported and will result in an error

**Examples:**
```bash
# Download latest version (default)
VERSION=LATEST

# Download specific version
VERSION=2026.01.17-4b0f30090
```

**Error Handling:**
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

## Server Configuration

These variables configure the Hytale server's `config.json` file. All settings are optional and will only be applied if the variable is set. The configuration step runs automatically during container startup (step 3 of the entrypoint).

### `SERVER_NAME`

**Type:** String  
**Default:** `"Hytale Server"`  
**Description:** Name of the server displayed to players.

**Example:**
```bash
SERVER_NAME="My Awesome Server"
```

---

### `MOTD`

**Type:** String  
**Default:** `""` (empty)  
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
**Default:** `100`  
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

## JVM & Server Startup

### `INIT_MEMORY`

**Type:** String (Memory size)  
**Default:** `12G`  
**Description:** Initial Java heap size (JVM `-Xms` option).

**Format:** Use standard JVM memory format (e.g., `512M`, `2G`, `4096M`)

**Example:**
```bash
INIT_MEMORY=8G
```

---

### `MAX_MEMORY`

**Type:** String (Memory size)  
**Default:** `12G`  
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
**Description:** Additional JVM options to append to the base JVM arguments.

**Example:**
```bash
JVM_OPTS="-Dsome.property=value -XX:+SomeOption"
```

---

### `JVM_XX_OPTS`

**Type:** String  
**Default:** `""` (empty)  
**Description:** Additional JVM `-XX:` options to prepend to the base JVM arguments.

**Example:**
```bash
JVM_XX_OPTS="-XX:+UseZGC -XX:MaxMetaspaceSize=512M"
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

**Type:** String  
**Default:** Not set (uses server default)  
**Description:** Authentication mode for the server.

**Example:**
```bash
AUTH_MODE="online"
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
**Description:** Enable or disable the RCON plugin. When disabled, the plugin will not be downloaded or configured.

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
**Default:** `latest`  
**Description:** Version of the RCON plugin to download. Set to `latest` to automatically fetch the latest release from GitHub, or specify a specific version (e.g., `1.0.0`).

**Example:**
```bash
RCON_VERSION=latest
```

**Example (specific version):**
```bash
RCON_VERSION=1.0.0
```

---

### `RCON_HOST`

**Type:** String (IP address)  
**Default:** `127.0.0.1`  
**Description:** IP address to bind the RCON server to within the Docker container.

**Docker Container Behavior:**
- `127.0.0.1` (default): RCON is only accessible from within the container itself. **Not accessible from the host machine**, even if the port is mapped in `docker-compose.yml`.
- `0.0.0.0`: RCON binds to all interfaces within the container, making it accessible from the host machine (when port `25575` is mapped) and from other containers on the same Docker network.

**Security Considerations:**
- To access RCON from your host machine, you must set `RCON_HOST=0.0.0.0` **and** have the port mapped in `docker-compose.yml`.
- The port mapping in `docker-compose.yml` controls whether RCON is exposed to the host network.
- Even with `0.0.0.0`, RCON is only accessible through the mapped port, providing some isolation.
- Always use strong authentication (`RCON_PASSWORD` or `RCON_PASSWORD_HASH`) when exposing RCON to the network.
- Consider using Docker network isolation or firewall rules for additional security.

**Example (container-only access):**
```bash
RCON_HOST=127.0.0.1
```

**Example (accessible from host):**
```bash
RCON_HOST=0.0.0.0
```

---

### `RCON_PORT`

**Type:** Integer  
**Default:** `25575`  
**Description:** Port number for the RCON server to listen on.

**Example:**
```bash
RCON_PORT=25575
```

---

### `RCON_PASSWORD`

**Type:** String  
**Default:** Not set (empty)  
**Description:** Plain text password for RCON authentication. The password will be automatically hashed using SHA-256 with salt during container startup. If both `RCON_PASSWORD` and `RCON_PASSWORD_HASH` are provided, `RCON_PASSWORD_HASH` takes precedence.

**Security Note:** If neither `RCON_PASSWORD` nor `RCON_PASSWORD_HASH` is set, RCON will run in insecure mode (no authentication required). This is only recommended for local development/testing.

**Example:**
```bash
RCON_PASSWORD=MySecurePassword123
```

**Security Note:** Consider using Docker secrets or environment files for sensitive passwords.

---

### `RCON_PASSWORD_HASH`

**Type:** String  
**Default:** Not set (empty)  
**Description:** Pre-hashed password in the format `base64salt:base64hash`. This overrides `RCON_PASSWORD` if both are provided. You can generate a password hash using the plugin JAR or the Make command in the hytale-exp repository.

**Format:** `base64salt:base64hash`

**Example:**
```bash
RCON_PASSWORD_HASH=dGhpc2lzYXNsdA==:YW5kdGhpc2lzdGhlcGFzc3dvcmRoYXNo
```

---

### `RCON_MAX_CONNECTIONS`

**Type:** Integer  
**Default:** `10`  
**Description:** Maximum number of concurrent RCON connections allowed.

**Example:**
```bash
RCON_MAX_CONNECTIONS=10
```

---

### `RCON_MAX_FRAME_SIZE`

**Type:** Integer  
**Default:** `4096`  
**Description:** Maximum RCON frame size in bytes.

**Example:**
```bash
RCON_MAX_FRAME_SIZE=4096
```

---

### `RCON_READ_TIMEOUT_MS`

**Type:** Integer  
**Default:** `30000`  
**Description:** Read timeout for RCON connections in milliseconds.

**Example:**
```bash
RCON_READ_TIMEOUT_MS=30000
```

---

### `RCON_CONNECTION_TIMEOUT_MS`

**Type:** Integer  
**Default:** `5000`  
**Description:** Connection timeout for RCON connections in milliseconds.

**Example:**
```bash
RCON_CONNECTION_TIMEOUT_MS=5000
```

---

### Automatic rcon-cli Configuration

The container automatically creates a `.rcon-cli.yaml` configuration file in the home directory (`~/.rcon-cli.yaml`) during RCON setup. This allows you to use the `rcon-cli` command without specifying `--host`, `--port`, or `--password` arguments.

**Configuration file location:** `~/.rcon-cli.yaml`

**Contents:**
- `host`: Set from `RCON_HOST` environment variable
- `port`: Set from `RCON_PORT` environment variable
- `password`: Set from `RCON_PASSWORD` environment variable (only if `RCON_PASSWORD` is provided)

**Usage:**
```bash
# If RCON_PASSWORD is set, you can use rcon-cli directly:
docker compose exec hytale rcon-cli list
docker compose exec hytale rcon-cli "say Hello!"
```

**Note:** The configuration file is created with permissions `600` (read/write for owner only) for security.

---

## Authentication

> **Note:** Authentication is handled automatically via `hy-auth.sh` during container startup. Credentials are stored in `/data/auth.json`. These environment variables are **not currently used** - authentication tokens are read from the JSON file, not environment variables.

The following variables are documented for reference but are not actively used by the current entrypoint:

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
      - HOST_GID=${GID:-1001}
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
# Container permissions
UID=1000
GID=1001

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
  - HOST_GID=${GID:-1001}
  - SERVER_NAME=${SERVER_NAME:-Hytale Server}
  - MAX_PLAYERS=${MAX_PLAYERS:-100}
```

### Command line

```bash
docker run -e HOST_UID=1000 -e HOST_GID=1001 \
  -e SERVER_NAME="My Server" \
  -e MAX_PLAYERS=50 \
  -e INIT_MEMORY=8G -e MAX_MEMORY=16G \
  -e BACKUP_DIR=/backup \
  -e BACKUP_FREQUENCY=60 \
  -v ./data:/data \
  -v ./backups:/backup \
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

