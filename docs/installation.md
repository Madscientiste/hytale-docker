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

## Automated Builds

GitHub Actions automatically builds and publishes Docker images to GitHub Container Registry on:
- Pushes to `main` or `develop` branches
- Tagged releases (e.g., `v1.0.0`)
- Manual workflow dispatch

Images are built for `linux/amd64` platforms.

`linux/arm64` hasn't been tested, but should be supported, please report any issues if you encounter any.

