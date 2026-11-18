# Installation Guide

## Using Docker Compose (Recommended)

This is the recommended way to set up and run the Hytale server.

Create a `docker-compose.yml` file:

```yaml
services:
  hytale:
    image: ghcr.io/madscientiste/hytale-docker:latest
    restart: unless-stopped
    stop_grace_period: 60s   # time to save the world when stopping
    container_name: hytale
    tty: true
    stdin_open: true
    environment:
      # Container & Permissions
      - HOST_UID=${UID:-1000}
      - HOST_GID=${GID:-1000}
      
      # Logging
      - LOG_LEVEL=INFO
      
      # Server Download
      - VERSION=LATEST
      - PATCHLINE=release
      
      # Server Configuration
      - SERVER_NAME=My Hytale Server
      - MOTD=Welcome to our Hytale server!
      - MAX_PLAYERS=50
      - DEFAULT_GAME_MODE=Adventure
      
      # JVM Memory
      - INIT_MEMORY=8G
      - MAX_MEMORY=16G
      
      # Backups
      - ENABLE_BACKUPS=true
      - BACKUP_FREQUENCY=30
      - BACKUP_MAX_COUNT=5
      
      # RCON
      - RCON_ENABLED=true
      - RCON_HOST=0.0.0.0   # random password in data/.rcon-password; see docs/rcon.md
      - RCON_PORT=25575
    volumes:
      - "./data:/data"
    ports:
      - "5520:5520/udp"   # Hytale game port
      - "127.0.0.1:25575:25575/tcp" # RCON, this host only
```

Then run:
```bash
docker compose up -d
```

Be sure to take a look at the logs when the server is starting up, and authenticate if it prompts you to.
```bash
docker compose logs -f hytale
```

## Using Pre-built Images

Images are automatically built and published to GitHub Container Registry:

```bash
docker pull ghcr.io/madscientiste/hytale-docker:latest
docker run -it --rm \
  -v $(pwd)/data:/data \
  -p 5520:5520/udp \
  ghcr.io/madscientiste/hytale-docker:latest
```

## Building Locally

1. **Build the container:**
   ```bash
   docker build -t hytale-server .
   ```

2. **Run the server:**
   ```bash
   docker run -it --rm \
     -v $(pwd)/data:/data \
     -p 5520:5520/udp \
     hytale-server
   ```

## Platform Compatibility

Tested platforms (does not include ARM devices):
- Arch Linux
- Ubuntu 24.04
- Windows -> Not yet tested

## Hardware UUID (machine ID)

The server needs a stable "hardware UUID". It encrypts its saved credentials (`auth.enc`) with a key derived from it, so if the ID changes, the saved login can no longer be read.

On Linux the server reads `/etc/machine-id` first. The container handles this for you:
- On the first start it generates an ID and saves it to `/data/machine-id`.
- On every later start it reuses that file, so the ID stays the same.
- To set your own, use `MACHINE_ID` (a UUID or 32 hex characters).

No `tmpfs` mount or access to the host's `/sys` is needed. Earlier versions of this image asked for a `tmpfs` mount on `/sys/class/dmi/id`; it is no longer used and can be removed.

**Note:** this needs the container to start as root (the default). If you run it with a `user:` override, `/etc/machine-id` cannot be written.

## Automated Builds

GitHub Actions automatically builds and publishes Docker images to GitHub Container Registry on:
- Pushes to `main` or `develop` branches
- Tagged releases (e.g., `v1.0.0`)
- Manual workflow dispatch

Images are built for `linux/amd64` platforms.

`linux/arm64` hasn't been tested, but should be supported, please report any issues if you encounter any.

