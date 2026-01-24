# Installation Guide

## Using Docker Compose (Recommended)

This is the recommended way to set up and run the Hytale server.

Create a `docker-compose.yml` file:

```yaml
services:
  hytale:
    image: ghcr.io/madscientiste/hytale-server:latest
    restart: unless-stopped
    container_name: hytale
    tty: true
    stdin_open: true
    environment:
      # Container & Permissions
      - HOST_UID=${UID:-1000}
      - HOST_GID=${GID:-1001}
      
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
      - RCON_PASSWORD=YourSecurePassword
      - RCON_HOST=0.0.0.0
      - RCON_PORT=25575
    volumes:
      - "./data:/data"
    tmpfs:
      - /sys/class/dmi/id:rw,noexec,nosuid,size=1m  # Required for hardware UUID (Linux)
    ports:
      - "5520:5520/udp"   # Hytale game port
      - "25575:25575/tcp" # RCON port
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
docker pull ghcr.io/madscientiste/hytale-server:latest
docker run -it --rm \
  -v $(pwd)/data:/data \
  -p 5520:5520/udp \
  ghcr.io/madscientiste/hytale-server:latest
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

## Hardware UUID Configuration (Linux)

The Hytale server requires access to hardware UUID information for telemetry purposes. On Linux systems, this requires a tmpfs mount to make the DMI directory writable.

**Why is tmpfs needed?**

The server tries to read `/sys/class/dmi/id/product_uuid`, but:
- `/sys` is read-only in Docker containers
- The host's DMI files may have restrictive permissions (root-only)
- The server runs as a non-root user and cannot read these files

The tmpfs mount overrides the read-only `/sys/class/dmi/id` directory with a writable version, allowing the container to create a `product_uuid` file with proper permissions.

**Configuration:**

The `docker-compose.yml` example above includes the required tmpfs mount:
```yaml
tmpfs:
  - /sys/class/dmi/id:rw,noexec,nosuid,size=1m
```

This mount is **required on Linux** to prevent hardware UUID errors. Without it, you may see:
```
java.lang.RuntimeException: Failed to get hardware UUID for Linux - all methods failed
```

**Note:** This error is non-critical (used for telemetry/analytics) and the server will continue to function, but the tmpfs mount eliminates the error.

**Additional Note:** At this time, the only reliable solution requires binding to the host's `/sys` directory, unless a custom mod is developed for the Hytale server to retrieve the hardware UUID directly from the container. Creating such a mod is not currently planned by me.

**Windows Users:**

The tmpfs mount configuration has not been tested on Windows containers. If you're running on Windows, you may need to adjust or omit this configuration. Please report any issues you encounter.

## Automated Builds

GitHub Actions automatically builds and publishes Docker images to GitHub Container Registry on:
- Pushes to `main` or `develop` branches
- Tagged releases (e.g., `v1.0.0`)
- Manual workflow dispatch

Images are built for `linux/amd64` platforms.

`linux/arm64` hasn't been tested, but should be supported, please report any issues if you encounter any.

