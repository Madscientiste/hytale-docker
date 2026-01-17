<div align="center">
  <img src="https://hytale.com/static/images/logo.png" alt="Hytale Logo" width="300">
</div>

# Hytale Server Containerized

A Docker container for running Hytale game servers with automated authentication, server file management, and configuration.

> [!NOTE] 
> This project is still a work in progress. I originally created this container for personal use on my NAS, so my friends and I could easily play together. While it works well for my needs, there are areas I plan to improve and additional features to add for a more robust, production-ready setup. I'm sharing it here in the hope that it helps others, and I'm open to feedback and contributions!
>
> I was able to point my domain's A record to my VPS and was able to connect to the Hytale server using my domain name, despite their warning about unsupported domains.
> 
> This project should stay alive for awhile, i'll be maintaining it and adding features as i need them.
> 
> If you have any feature requests, please open an issue; I'm happy to consider them and discuss how we might implement your ideas.

## Quick Start

### Using Docker Compose (Recommended)

**This is the recommended way to set up and run the Hytale server.**

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
      - HOST_UID=${UID:-1000}
      - HOST_GID=${GID:-1001}
    volumes:
      - "./data:/data"
    ports:
      - "5520:5520/udp" # Hytale UDP/QUIC
      - "25575:25575/tcp" # RCON TCP
```

Then run:
```bash
docker compose up -d
```

Besure to take a look at the logs when the server is starting up, and authenticate if it prompts you to.
```bash
docker compose logs -f hytale
```

### Using Pre-built Images (Docker CLI)

Images are automatically built and published to GitHub Container Registry:

```bash
docker pull ghcr.io/madscientiste/hytale-server:latest
docker run -it --rm \
  -v $(pwd)/data:/data \
  -p 5520:5520/udp \
  ghcr.io/madscientiste/hytale-server:latest
```

### Building Locally

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

## First-time Authentication
   - The container will prompt you to visit a URL and enter a device code
   - Complete authentication in your browser
   - Credentials will be saved to `/data/auth.json`

## Example Logs

When starting the container for the first time, you'll see output similar to this:

```bash
Attaching to hytale
hytale  | [INFO] Modifying hytale user to match host UID=1000 GID=1001
hytale  | [INFO] Creating hytale group with GID 1001
hytale  | [INFO] Creating hytale user with UID 1000
hytale  | [INFO] Fixing ownership of /data to 1000:1001
hytale  | 
hytale  | ==========================================
hytale  |   Hytale Server Startup
hytale  | ==========================================
hytale  | 
hytale  | Step 1: Authenticating with Hytale
hytale  | Step 1: Requesting device code
hytale  | 
hytale  | ==========================================
hytale  |   Hytale Server Authorization Required
hytale  | ==========================================
hytale  | 
hytale  | [INFO] Please visit this URL in your browser:
hytale  | 
hytale  | [INFO] https://oauth.accounts.hytale.com/oauth2/device/verify?user_code=pNxEEsJv
hytale  | 
hytale  | [INFO] Or visit:
hytale  | [INFO] https://oauth.accounts.hytale.com/oauth2/device/verify
hytale  | 
hytale  | [INFO] And enter this code:
hytale  |   pNxEEsJv
hytale  | 
hytale  | [INFO] Waiting for authorization...
hytale  | ....
hytale  | Authorization successful!
hytale  | Step 4: Fetching available profiles...
hytale  | [INFO] Found profile: username (xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)
hytale  | Step 5: Creating game session...
hytale  | Game session created successfully!
hytale  | Step 6: Saving credentials to /data/auth.json...
hytale  | 
hytale  | 
hytale  | ==========================================
hytale  |   Authentication Complete!
hytale  | ==========================================
hytale  | 
hytale  | [INFO] Credentials saved to: /data/auth.json
hytale  | [INFO] Session expires at: 2026-01-14T20:11:32.020458214Z
hytale  | 
hytale  | [INFO] You can now start the Hytale server.
hytale  | 
hytale  | Step 2: Checking server files
hytale  | 
hytale  | ==========================================
hytale  |   Downloading Hytale Server
hytale  | ==========================================
hytale  | 
hytale  | [INFO] Version: LATEST
hytale  | [INFO] Patchline: release
hytale  | [INFO] Using credentials: /data/auth.json
hytale  | Step 1: Getting version manifest for patchline: release
hytale  | [SUCCESS] Got signed manifest URL
hytale  | Step 2: Fetching manifest content...
hytale  | [SUCCESS] Manifest retrieved
hytale  | [INFO]   Version: 2026.01.13-50e69c385
hytale  | [INFO]   Download path: builds/release/2026.01.13-50e69c385.zip
hytale  | [INFO]   SHA256: bf32f635771ec383...
hytale  | Step 3: Getting signed download URL...
hytale  | [SUCCESS] Got signed download URL (expires in 6 hours)
hytale  | Step 4: Downloading game file to temporary location...
hytale  | [INFO] Output: /data/.tmp-download/game.zip
hytale  | [INFO] This may take a while...
```

The container will:
1. Set up the user and group permissions to match your host system
2. Display the authentication URL and device code
3. Wait for you to complete the OAuth flow in your browser
4. Fetch your Hytale profile and create a game session
5. Save credentials to `/data/auth.json` for future use
6. Download the latest server files automatically
7. Continue with server configuration and startup

## Configuration

See [docs/env-variables.md](docs/env-variables.md) for all available environment variables.

### Key Environment Variables

- `PATCHLINE`: Server patchline (default: `release`)
- `MAX_PLAYERS`: Maximum number of players (default: 20)
- `SERVER_NAME`: Server name
- `MOTD`: Message of the day
- `INIT_MEMORY`: Initial JVM heap size (default: `12G`)
- `MAX_MEMORY`: Maximum JVM heap size (default: `12G`)
- `ENABLE_BACKUPS`: Enable/disable automatic backups (default: `true`)
- `BACKUP_DIR`: Backup directory path (default: `/data/backups`)
- `BACKUP_FREQUENCY`: Backup interval in minutes (default: `30`)
- `BACKUP_MAX_COUNT`: Maximum number of backups to keep (default: `5`)

## RCON Support

The container includes built-in support for the [RCON plugin](https://github.com/Madscientiste/hytale-exp), which provides remote console access to your Hytale server using the standard RCON protocol.

### Features

- **Automatic Download**: The RCON plugin is automatically downloaded from GitHub releases during container startup
- **Automatic Configuration**: Plugin configuration is automatically added to `config.json` based on environment variables
- **Password Hashing**: Plain text passwords are automatically hashed using SHA-256 with salt
- **Secure by Default**: Defaults to localhost-only binding (`127.0.0.1`)

### Quick Start

RCON is enabled by default. To use it with a password:

```yaml
environment:
  - RCON_PASSWORD=MySecurePassword123
  - RCON_PORT=25575
```

The container will automatically:
1. Download the latest RCON plugin from GitHub releases
2. Generate a password hash from your plain text password
3. Create/update the RCON configuration file at `configs/com.madscientiste.rcon.json`
4. Start the RCON server when the Hytale server starts

**Note:** If you don't set `RCON_PASSWORD`, the plugin will auto-generate a secure random password on first start. **Check the server logs immediately** to find and save the generated password - it won't be shown again!

### Configuration

Key environment variables:

- `RCON_ENABLED`: Enable/disable RCON (default: `true`)
- `RCON_VERSION`: Plugin version (default: `latest`)
- `RCON_HOST`: Bind address (default: `127.0.0.1`)
- `RCON_PORT`: Port number (default: `25575`)
- `RCON_PASSWORD`: Plain text password (will be hashed automatically)
- `RCON_PASSWORD_HASH`: Pre-hashed password (format: `base64salt:base64hash`)

The RCON configuration is stored in `/data/configs/com.madscientiste.rcon.json`. This file is automatically created/updated based on your environment variables. You can also edit it manually if needed.

**Auto-generated passwords:** If you don't set a password, the plugin will generate one on first start. Check the server logs for the password and save it immediately!

See [docs/env-variables.md](docs/env-variables.md) for complete RCON configuration options.

### Generating Password Hashes

If you prefer to generate the password hash manually, you can use the plugin JAR:

```bash
# Inside the container, after the plugin is downloaded
docker compose exec hytale java -cp /data/mods/rcon-*.jar com.madscientiste.rcon.infrastructure.AuthenticationService your_password_here
```

Or use the Make command from the [hytale-exp repository](https://github.com/Madscientiste/hytale-exp):

```bash
make password PASSWORD=your_password_here
```

Then add the generated hash to `/data/configs/com.madscientiste.rcon.json`:

```json
{
  "passwordHash": "dGhpc2lzYXNsdA==:YW5kdGhpc2lzdGhlcGFzc3dvcmRoYXNo"
}
```

### Security Considerations

**Authentication:**
- Always set `RCON_PASSWORD` or `RCON_PASSWORD_HASH` for production use
- If no password is set, the plugin will auto-generate one - **save it from the server logs immediately!**
- Without a password, anyone can connect and execute commands
- Use strong passwords and keep your `configs/com.madscientiste.rcon.json` file secure

**Network Exposure:**
- Default binding (`127.0.0.1`) restricts access to localhost only
- If exposing RCON over the network, use firewall IP whitelisting
- Do not expose the RCON port to the public internet unless absolutely necessary
- Consider using Docker network isolation for additional security

### Connecting to RCON

Once configured, you can connect using any RCON-compatible client:

**Using rcon-cli (inside container):**
The container includes `rcon-cli` pre-installed and preconfigured. A `.rcon-cli.yaml` configuration file is automatically created in the home directory with your RCON settings, so you can use `rcon-cli` without specifying host, port, or password:

```bash
# Execute a single command (no arguments needed if RCON_PASSWORD is set)
docker compose exec hytale rcon-cli list

# Or enter the container and use rcon-cli interactively
docker compose exec hytale sh
rcon-cli list
rcon-cli help
rcon-cli "say Hello from RCON!"
```

**Note:** If `RCON_PASSWORD` is not set, you'll need to provide the password:
```bash
docker compose exec hytale rcon-cli --password MyPassword list
```

The configuration file is located at `~/.rcon-cli.yaml` and contains:
- `host`: RCON host (from `RCON_HOST` env var)
- `port`: RCON port (from `RCON_PORT` env var)  
- `password`: RCON password (from `RCON_PASSWORD` env var, if set)

**Using rcon-cli (from host):**
If you have `rcon-cli` installed on your host machine:
```bash
rcon-cli --host 127.0.0.1 --port 25575 --password MySecurePassword123 list
```

**Using mcrcon (from host):**
```bash
mcrcon -H 127.0.0.1 -P 25575 -p MySecurePassword123 "list"
```

### Disabling RCON

To disable RCON:

```yaml
environment:
  - RCON_ENABLED=false
```

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
│   │   ├── 04-setup-rcon.sh     # RCON plugin setup
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
- Ubuntu 24.04
- Windows -> Not yet tested

## Misc

> [!WARNING]
> This project is not affiliated with Hytale or its developers. It is a personal project created for educational and recreational purposes.

