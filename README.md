<div align="center">
  <img src="https://hytale.com/static/images/logo.png" alt="Hytale Logo" width="300">
</div>

# Hytale Server Containerized

A Docker container for running Hytale game servers with automated authentication, server file management, and configuration.

> [!NOTE] 
> This project is still under experimentation. I initially built this container for personal use on my NAS so my friends and I could easily play together. While it suits my current needs, there are improvements and new features I plan to add to make it more robust and production-y ready. I’m sharing it here in hopes it’s helpful to others, and I welcome any feedback or contributions!
>
>
> I plan to maintain this project and continue adding features as I need them, so it should remain active for the foreseeable future.
>
> If you have feature requests or suggestions, please open an issue; I'm happy to consider new ideas and discuss new implementations.

## Features

- **Automated OAuth2 authentication** with token refresh
- **Auto-downloads server files** from Hytale's CDN
- **Smart update checking** with cooldown protection
- **In-container restarts** (`hy-restart`) and opt-in automatic restarts
- **Mods from download links** (`MODS`)
- **Hytale's recommended plugins** installed by default (WebServer, Query, Prometheus metrics, PerformanceSaver)
- **Health check** for `docker ps`, Dokploy, Portainer and similar tools
- **Built-in RCON support** for remote server management
- **Automatic backups** with configurable retention
- **Multi-platform images** (linux/amd64, linux/arm64)
- **Extensive configuration** via environment variables

## Quick Start

Create a `docker-compose.yml` file:
```yaml
services:
  hytale:
    image: ghcr.io/madscientiste/hytale-docker:latest
    # Or build locally: build: .
    restart: unless-stopped
    stop_grace_period: 60s   # time to save the world when stopping
    container_name: hytale
    tty: true
    stdin_open: true
    environment:
      # Container & Permissions
      - HOST_UID=${UID:-1000}
      - HOST_GID=${GID:-1001}
      
      # Server Configuration
      - SERVER_NAME=My Hytale Server
      - MOTD=Welcome to our Hytale server!
      - MAX_PLAYERS=50
      
      # RCON: no password needed, a random one is saved in data/.rcon-password
      - RCON_HOST=0.0.0.0  # listen inside the container; the port line below limits it to this host
    volumes:
      - "./data:/data"
    ports:
      - "5520:5520/udp"   # Hytale UDP/QUIC
      - "127.0.0.1:25575:25575/tcp" # RCON, this host only (never open it to the internet)
```

Start the server:
```bash
docker compose up -d
docker compose logs -f  # Watch for authentication prompt on first run
```

**First run:** The server will prompt you to authenticate via browser. Follow the URL and enter the code shown in the logs. See the [Authentication Guide](docs/authentication.md) for details.

**Configuration:** When you use this repository's `docker-compose.yml`, keep your settings in a `.env` file instead of editing the compose file:
```bash
cp .env.example .env   # then edit .env
docker compose up -d   # apply changes
```
`.env` is ignored by git, so your passwords stay local. See [Environment Variables](docs/env-variables.md) for all options.

### Updating Your Server

The server updates only when it restarts, and only when `VERSION=LATEST` (the default). Pin a version (for example `VERSION=0.7.7`) to stay on it. To switch an installed server to the pinned version, start once with `FORCE_DOWNLOAD=true`.

**Restart (and update) without stopping the container:**
```bash
docker exec hytale hy-restart          # warns players, restarts in 5 minutes
docker exec hytale hy-restart --now    # restarts immediately
docker exec hytale hy-restart --cancel # cancels a pending restart
```

**Automatic restarts** are off by default. Set `RESTART_MODE=schedule` (daily at `RESTART_TIME`) or `RESTART_MODE=on-update` (when a new version is out).

See [Update Management](docs/update-management.md) for details.

### Upgrading from the January 2026 version

If you use your own `docker-compose.yml` from back then, change these RCON lines (the old example was unsafe):

| Old line | Change to | Why |
|---|---|---|
| `"25575:25575/tcp"` | `"127.0.0.1:25575:25575/tcp"` | The old line opens RCON on every network interface, past firewalls such as ufw |
| `RCON_PASSWORD=verysecurepassword` | delete it | A random password is made and saved in `data/.rcon-password` |
| `RCON_VERSION=latest` | delete it | The image then installs the RCON plugin it was tested with and checks its checksum |

Also add `stop_grace_period: 60s` so the world is saved when the container stops.

What else changes when you update:

- **Four recommended plugins are installed** (web server, Query, metrics, PerformanceSaver). PerformanceSaver lowers the tick rate and view radius when the server is under load. Turn any of them off with `ENABLE_WEBSERVER=false`, `ENABLE_QUERY=false`, `ENABLE_METRICS=false` or `ENABLE_PERFORMANCE_SAVER=false`. See [Recommended plugins](docs/env-variables.md#recommended-plugins).
- **An empty `RCON_PASSWORD` now means a random password**, not "no password".
- **The image has a health check**, shown as `healthy` or `unhealthy` in `docker ps`.
- **A pinned `VERSION` now warns when another version is installed.** As before, it is not downloaded over an installed server: start once with `FORCE_DOWNLOAD=true` to switch versions.
- **RCON plugin 1.2.0 logs a warning at every start** because `RCON_HOST=0.0.0.0` is not a loopback address. In Docker this is expected: the port line keeps RCON on this host. See [Who can connect](docs/rcon.md#who-can-connect).
- **New password hashes use a slow, safer format** (`pbkdf2-sha512:...`). An old `RCON_PASSWORD_HASH` still works, but the plugin warns about it at every start: make a new one with `gen-psswd`. If you also set `RCON_PASSWORD`, it must match the hash, or the container stops.
- **RCON numbers are checked.** A value outside the plugin's range (for example `RCON_READ_TIMEOUT_MS` above 300000) stops the container with an error, instead of RCON silently staying off. With an `RCON_VERSION` older than 1.2.0, only whole numbers are checked.
- **Still on a January 2026 server build?** The RCON plugin this image installs (1.2.0) was built for both, but was only tested on 0.7.7. If `rcon-cli` stops working, set `RCON_VERSION=rcon-v1.1.0`.

## Documentation

### Getting Started
- **[Installation Guide](docs/installation.md)** - Docker Compose, CLI, building from source
- **[Authentication Guide](docs/authentication.md)** - First-time OAuth setup and example logs
- **[Update Management](docs/update-management.md)** - Automatic update checking and version control

### Configuration
- **[Environment Variables](docs/env-variables.md)** - Complete configuration reference
- **[Performance Tuning](docs/performance.md)** - Memory allocation and JVM optimization
- **[RCON Setup](docs/rcon.md)** - Remote console configuration and security

### Reference
- **[Update Management](docs/update-management.md)** - Automatic update checking and version control
- **[Hytale API](docs/misc/hytale-api.md)** - API endpoints documentation
- **[hy-auth CLI](docs/misc/hy-auth.md)** - OAuth2 authentication utility
- **[hy-downloader CLI](docs/misc/hy-downloader.md)** - Server file download utility
- **rcon-cli** - send console commands: `docker compose exec hytale rcon-cli who` (see [RCON Setup](docs/rcon.md))
- **gen-psswd** - RCON password hash generator (see [RCON Setup](docs/rcon.md))

## Project Structure

```
hytale-docker/
├── Dockerfile              # Container definition
├── docker-compose.yml      # Docker Compose configuration
├── scripts/
│   ├── steps/              # Startup sequence scripts
│   │   ├── 00-entrypoint.sh
│   │   ├── 01-download-server.sh
│   │   ├── 02-configure-server.sh
│   │   ├── 03-load-auth.sh
│   │   ├── 04-setup-rcon.sh
│   │   ├── 05-install-mods.sh
│   │   ├── 06-install-plugins.sh
│   │   └── 09-start-server.sh
│   └── tools/              # Utility scripts
│       ├── hy-auth.sh      # OAuth2 authentication tool
│       ├── hy-downloader.sh # Server file downloader
│       ├── hy-restart.sh   # Restart the server inside the container
│       ├── hy-scheduler.sh # Background jobs (login refresh, automatic restarts)
│       ├── hy-health.sh    # Docker health check
│       ├── rcon-cli.sh     # rcon-cli wrapper (finds the RCON password)
│       └── gen-psswd.sh    # RCON password hash generator
└── docs/                   # Documentation
```

## Contributing

This project is actively maintained. If you have feature requests or encounter issues, please open an issue on GitHub. I'm happy to discuss and consider new ideas!

## Disclaimer

> [!WARNING]
> This project is not affiliated with Hytale or its developers. It is a personal project created for educational and recreational purposes.