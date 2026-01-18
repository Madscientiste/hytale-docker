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
- **Built-in RCON support** for remote server management
- **Automatic backups** with configurable retention
- **Multi-platform images** (linux/amd64, linux/arm64)
- **Extensive configuration** via environment variables

## Quick Start

Create a `docker-compose.yml` file:
```yaml
services:
  hytale:
    image: ghcr.io/madscientiste/hytale-server:latest
    # Or build locally: build: .
    restart: unless-stopped
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
      
      # RCON
      - RCON_PASSWORD=YourSecurePassword  # Set your RCON password
      - RCON_HOST=0.0.0.0  # Allow RCON access from host (default: 127.0.0.1 = container only)
    volumes:
      - "./data:/data"
    ports:
      - "5520:5520/udp"   # Hytale UDP/QUIC
      - "25575:25575/tcp" # RCON TCP (requires RCON_HOST=0.0.0.0 to access from host)
```

Start the server:
```bash
docker compose up -d
docker compose logs -f  # Watch for authentication prompt on first run
```

**First run:** The server will prompt you to authenticate via browser. Follow the URL and enter the code shown in the logs. See the [Authentication Guide](docs/authentication.md) for details.

**Configuration:** See [Environment Variables](docs/env-variables.md) for all available options.

## Documentation

### Getting Started
- **[Installation Guide](docs/installation.md)** - Docker Compose, CLI, building from source
- **[Authentication Guide](docs/authentication.md)** - First-time OAuth setup and example logs

### Configuration
- **[Environment Variables](docs/env-variables.md)** - Complete configuration reference
- **[Performance Tuning](docs/performance.md)** - Memory allocation and JVM optimization
- **[RCON Setup](docs/rcon.md)** - Remote console configuration and security

### Reference
- **[Hytale API](docs/misc/hytale-api.md)** - API endpoints documentation
- **[hy-auth CLI](docs/misc/hy-auth.md)** - OAuth2 authentication utility
- **[hy-downloader CLI](docs/misc/hy-downloader.md)** - Server file download utility
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
│   │   └── 09-start-server.sh
│   └── tools/              # Utility scripts
│       ├── hy-auth.sh      # OAuth2 authentication tool
│       ├── hy-downloader.sh # Server file downloader
│       └── gen-psswd.sh    # RCON password hash generator
└── docs/                   # Documentation
```

## Contributing

This project is actively maintained. If you have feature requests or encounter issues, please open an issue on GitHub. I'm happy to discuss and consider new ideas!

## Disclaimer

> [!WARNING]
> This project is not affiliated with Hytale or its developers. It is a personal project created for educational and recreational purposes.
