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

With `0.0.0.0`, the plugin logs a warning at every start: "RCON is listening on 0.0.0.0, which is not a loopback address". In Docker this is expected; the port line keeps RCON on this host.

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

Then set `RCON_PASSWORD_HASH=<hash>`. A hash in `RCON_PASSWORD` works the same way. With a hash only, the image cannot log in itself: `rcon-cli` needs `--password`, players get no restart warnings, and the health check only checks that the server process runs.

`gen-psswd` reads the password from the prompt or stdin (`echo "$PW" | docker compose exec -T hytale gen-psswd`). Passing it as an argument also works, but then it shows in `ps` and your shell history.

The hash looks like `pbkdf2-sha512:210000:...`. It needs plugin 1.2.0 or newer. For an older plugin (for example `RCON_VERSION=rcon-v1.1.1`), use `gen-psswd --old`. That old, fast format still works on 1.2.0, but the plugin warns about it at every start; make a new hash to stop the warning.

If you set both `RCON_PASSWORD` and `RCON_PASSWORD_HASH`, they must match. Otherwise the container stops with "RCON_PASSWORD does not match RCON_PASSWORD_HASH", so the image never logs in with a wrong password.

## Plugin version

By default (`RCON_VERSION` empty) the image installs the plugin release it was tested with, and checks its sha256 checksum. A download that does not match is refused, and an installed jar that does not match is moved to `data/.disabled-plugins` and downloaded again.

- `RCON_VERSION=latest`: the newest release on GitHub, not checked.
- `RCON_VERSION=rcon-v1.1.0` (a release tag, or just `1.1.0`): that release, 1.1.0 or newer. A value that starts with a digit, or `v` and a digit, becomes `rcon-v<version>`, so 1.0.0 (tag `v1.0.0`) cannot be chosen. Only the tested release (`rcon-v1.2.0`) is checked.

Only one RCON plugin version is kept in `data/mods`; other versions are moved to `data/.disabled-plugins`. If GitHub cannot be reached with `RCON_VERSION=latest`, the installed version is kept.

## Configuration

| Variable | Default | What it does |
|---|---|---|
| `RCON_ENABLED` | `true` | `false` turns RCON off (no plugin, no player warnings, process-only health check); an installed plugin moves to `data/.disabled-plugins` |
| `RCON_VERSION` | empty | Plugin version (see above) |
| `RCON_HOST` | `0.0.0.0` in compose | Listen address inside the container |
| `RCON_PORT` | `25575` | Port |
| `RCON_PASSWORD` | empty | Your password; empty: a random one in `data/.rcon-password` |
| `RCON_PASSWORD_HASH` | empty | Hash only (see above); wins over `RCON_PASSWORD` for the plugin |
| `RCON_COMMAND_TIMEOUT` | `10` | Seconds the health check and restart warnings wait for an answer; not in `docker-compose.yml` |

The plugin's own file is `data/configs/com.madscientiste.rcon.json`; the image updates it on every start. All options and their allowed ranges: [env-variables.md](env-variables.md#rcon-configuration). A number outside its range stops the container with an error, because the plugin would refuse the config and RCON would stay off.

## Disabling RCON

```bash
# .env
RCON_ENABLED=false
```
