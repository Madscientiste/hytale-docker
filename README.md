<div align="center">
  <img src="https://hytale.com/static/images/logo.png" alt="Hytale Logo" width="300">
</div>

# Heetail - Hytale Server Container

A Docker container for running Hytale game servers with automated authentication, server file management, and configuration.

## Features

- **Automated OAuth2 Authentication**: Device code flow authentication with automatic token refresh
- **Automatic Server Downloads**: Downloads and updates server files from Hytale's CDN
- **Configuration Management**: Server configuration via environment variables
- **Secure Credential Handling**: Encrypted credential storage with automatic management
- **Alpine-based**: Lightweight container based on Eclipse Temurin JRE

## Quick Start

### Using Docker Compose (Recommended)

**This is the recommended way to set up and run the Hytale server.**

Create a `docker-compose.yml` file:

```yaml
services:
  hytale:
    image: ghcr.io/Madscientiste/hytale:latest
    # Or build locally: build: .
    restart: unless-stopped
    container_name: hytale
    tty: true
    stdin_open: true
    environment:
      - HOST_UID=${UID:-1000}
      - HOST_GID=${GID:-1001}
    volumes:
      - "./data:/data"
    ports:
      - "5520:5520/udp" # Hytale UDP/QUIC
```

Then run:
```bash
docker-compose up -d
```

### Using Pre-built Images (Docker CLI)

Images are automatically built and published to GitHub Container Registry:

```bash
docker pull ghcr.io/Madscientiste/hytale:latest
docker run -it --rm \
  -v $(pwd)/data:/data \
  -p 5520:5520/udp \
  ghcr.io/Madscientiste/hytale:latest
```

### Building Locally

1. **Build the container:**
   ```bash
   docker build -t hytale .
   ```

2. **Run the server:**
   ```bash
   docker run -it --rm \
     -v $(pwd)/data:/data \
     -p 5520:5520/udp \
     hytale
   ```

## First-time Authentication
   - The container will prompt you to visit a URL and enter a device code
   - Complete authentication in your browser
   - Credentials will be saved to `/data/auth.json`

## Configuration

See [docs/env-variables.md](docs/env-variables.md) for all available environment variables.

### Key Environment Variables

- `PATCHLINE`: Server patchline (default: `release`)
- `MAX_PLAYERS`: Maximum number of players (default: 20)
- `SERVER_NAME`: Server name
- `MOTD`: Message of the day
- `INIT_MEMORY`: Initial JVM heap size (default: `12G`)
- `MAX_MEMORY`: Maximum JVM heap size (default: `12G`)

## Project Structure

```
heetail/
├── Dockerfile              # Container definition
├── docker-compose.yml      # Docker Compose configuration
├── scripts/
│   ├── steps/              # Startup sequence scripts
│   │   ├── 00-entrypoint.sh    # Main entrypoint
│   │   ├── 01-download-server.sh
│   │   ├── 02-configure-server.sh
│   │   ├── 03-load-auth.sh
│   │   └── 09-start-server.sh
│   └── tools/
│       └── hy-auth.sh      # OAuth2 authentication tool
└── docs/
    ├── env-variables.md    # Environment variables documentation
    ├── hytale-api.md       # Hytale API documentation
    └── hy-auth.md          # Authentication tool documentation
```

## Authentication

The container uses OAuth2 Device Code Flow (RFC 8628) for authentication. Tokens are automatically refreshed when needed, and the container will skip refresh if tokens are still valid to avoid unnecessary API calls.

See [docs/hy-auth.md](docs/hy-auth.md) for detailed authentication documentation.

## API Documentation

See [docs/hytale-api.md](docs/hytale-api.md) for complete API endpoint documentation.

## CI/CD

GitHub Actions automatically builds and publishes Docker images to GitHub Container Registry on:
- Pushes to `main` or `develop` branches
- Tagged releases (e.g., `v1.0.0`)
- Manual workflow dispatch

Images are built for both `linux/amd64` and `linux/arm64` platforms.

Tested platforms:
- Arch Linux
- Windows -> Not yet tested

## License

This project is provided as-is for educational and personal use.

