# RCON Configuration

## Overview

The container includes built-in support for the [RCON plugin](https://github.com/Madscientiste/hytale-exp), which provides remote console access to your Hytale server using the standard RCON protocol.

TODO: pin the version per release of the image.

### Features

- **Automatic Download**: The RCON plugin is automatically downloaded from GitHub releases during container startup
- **Automatic Configuration**: Plugin configuration is automatically added to `config.json` based on environment variables
- **Password Hashing**: Plain text passwords are automatically hashed using SHA-256 with salt
- **Secure by Default**: Defaults to localhost-only binding (`127.0.0.1`)

## Quick Start

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

## Configuration

Key environment variables:

- `RCON_ENABLED`: Enable/disable RCON (default: `true`)
- `RCON_VERSION`: Plugin version (default: `latest`)
- `RCON_HOST`: Bind address (default: `127.0.0.1`)
- `RCON_PORT`: Port number (default: `25575`)
- `RCON_PASSWORD`: Plain text password (will be hashed automatically)
- `RCON_PASSWORD_HASH`: Pre-hashed password (format: `base64salt:base64hash`)

The RCON configuration is stored in `/data/configs/com.madscientiste.rcon.json`. This file is automatically created/updated based on your environment variables. You can also edit it manually if needed.

**Auto-generated passwords:** If you don't set a password, the plugin will generate one on first start. Check the server logs for the password and save it immediately!

See [env-variables.md](env-variables.md) for complete RCON configuration options.

## Generating Password Hashes

### Using the gen-psswd Utility (Recommended)

The container includes a `gen-psswd` utility script that automatically locates the RCON plugin JAR and generates password hashes. The script uses a symlink created during container startup, so you don't need to know the JAR version or location.

```bash
# Generate hash from command line argument
docker compose exec hytale gen-psswd your_password_here

# Or pipe password (useful for scripts)
echo "your_password_here" | docker compose exec -T hytale gen-psswd
```

The script will output the password hash in the format `base64salt:base64hash`. You can then add it to `/data/configs/com.madscientiste.rcon.json`:

```json
{
  "passwordHash": "dGhpc2lzYXNsdA==:YW5kdGhpc2lzdGhlcGFzc3dvcmRoYXNo"
}
```

**Note:** The `gen-psswd` command is available in the container's PATH and automatically finds the RCON plugin JAR via a symlink created at `/data/.bin/rcon.jar` during container startup.

## Security Considerations

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

## Connecting to RCON

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

## Disabling RCON

To disable RCON:

```yaml
environment:
  - RCON_ENABLED=false
```

