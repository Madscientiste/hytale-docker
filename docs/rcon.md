# RCON

RCON is a remote console: it sends server commands such as `who`, `say` or `stop` to the running server. The image installs the [RCON plugin](https://github.com/Madscientiste/hytale-exp) and sets it up for you. It works with no settings.

## Quick Start

Nothing to set. On the first start the image:

1. Installs the RCON plugin version tested with this image, and checks its sha256 checksum.
2. Makes a random password and saves it in `data/.rcon-password` (only the server user can read it).
3. Starts RCON when the server starts.

Send commands from the host:

```bash
docker compose exec hytale rcon-cli who
docker compose exec hytale rcon-cli say "Hello from RCON!"
docker compose exec -it hytale rcon-cli      # interactive console
```

`rcon-cli` inside the container finds the password by itself. The image also uses RCON to warn players before a restart (`hy-restart`) and for the health check.

## Who can connect

- **Inside the container:** always (`docker compose exec hytale rcon-cli ...`). This needs no open port.
- **From the host:** `docker-compose.yml` publishes the port as `127.0.0.1:25575:25575`, so only programs on the host itself can connect.
- **From other machines:** not by default. RCON is not encrypted, and Docker's published ports bypass firewalls such as ufw. Don't open RCON to the internet. If you need it from another machine, use an SSH tunnel or a VPN to the host instead.

`RCON_HOST` is the address the plugin listens on **inside** the container. Keep `0.0.0.0` so the published port works; the port line in `docker-compose.yml` decides who can reach it.

## Your own password

To use your own password instead of the generated one:

```bash
# .env
RCON_PASSWORD=MySecurePassword123
```

To read the generated password (for a client on the host):

```bash
docker compose exec hytale cat /data/.rcon-password
```

To get a new random password, delete `data/.rcon-password` and restart.

### Password hash only

You can give the plugin only a hash, so the plaintext is not stored in the container:

```bash
docker compose exec hytale gen-psswd          # asks for the password, prints the hash
```

Then set `RCON_PASSWORD_HASH=<hash>`. With a hash only, the image cannot log in itself: `rcon-cli` needs `--password`, players get no restart warnings, and the health check only checks that the server process runs.

`gen-psswd` reads the password from the prompt or stdin (`echo "$PW" | docker compose exec -T hytale gen-psswd`). Passing it as an argument also works, but then it shows in `ps` and your shell history.

## Plugin version

By default (`RCON_VERSION` empty) the image installs the plugin release it was tested with, and checks its sha256 checksum. A download that does not match is refused, and an installed jar that does not match is moved to `data/.disabled-plugins` and downloaded again.

- `RCON_VERSION=latest`: the newest release on GitHub, not checked.
- `RCON_VERSION=rcon-v1.1.0` (any release tag, or just `1.1.0`): that release. Only the tested release (`rcon-v1.1.1`) is checked.

Only one RCON plugin version is kept in `data/mods`; other versions are moved to `data/.disabled-plugins`. If GitHub cannot be reached with `RCON_VERSION=latest`, the installed version is kept.

## Configuration

| Variable | Default | What it does |
|---|---|---|
| `RCON_ENABLED` | `true` | `false` turns RCON off (no plugin, no player warnings, process-only health check) |
| `RCON_VERSION` | empty | Plugin version (see above) |
| `RCON_HOST` | `0.0.0.0` in compose | Listen address inside the container |
| `RCON_PORT` | `25575` | Port |
| `RCON_PASSWORD` | empty | Your password; empty: a random one in `data/.rcon-password` |
| `RCON_PASSWORD_HASH` | empty | Hash only (see above); wins over `RCON_PASSWORD` for the plugin |

The plugin's own file is `data/configs/com.madscientiste.rcon.json`; the image updates it on every start. All options: [env-variables.md](env-variables.md#rcon-configuration).

## Disabling RCON

```bash
# .env
RCON_ENABLED=false
```
