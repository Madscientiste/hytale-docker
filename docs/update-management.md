# Server Update Management

## Overview

The server only updates when it restarts, and only when `VERSION=LATEST`:

- **`VERSION=LATEST`** (default): every restart checks for a new version and downloads it.
- **`VERSION=<version>`** (for example `0.7.7`): the server stays on that version. Nothing is checked or downloaded.

Nothing updates behind your back: a running server is never changed. Hytale's own built-in updater (`/update`) is switched off in this image, because the image manages updates itself.

## Restarting the Server

`hy-restart` restarts the game server inside the running container. The container stays up; the startup steps run again (login refresh, update check, configuration), then the server starts again.

```bash
docker exec hytale hy-restart              # warn players, restart in RESTART_WARN_MINUTES (default 5)
docker exec hytale hy-restart --now        # restart immediately
docker exec hytale hy-restart --minutes 10 # warn players, restart in 10 minutes
docker exec hytale hy-restart --cancel     # cancel a pending restart
```

- Players are warned in chat (`say`) when the countdown starts, at 1 minute and at 10 seconds. This needs RCON (on by default; it uses `RCON_PASSWORD` or the generated password). With RCON off, or only `RCON_PASSWORD_HASH`, the restart still happens, without warnings.
- `hy-restart` waits for the countdown. Use `docker exec -d hytale hy-restart` to start it and return immediately.
- A restart from `hy-restart` always checks for updates, skipping the 1-hour cooldown below.

> [!NOTE]
> `docker compose restart` restarts the whole container and also runs the update check. Variables typed on the host, such as `FORCE_UPDATE_CHECK=true docker compose restart`, do **not** reach the container; set them in `docker-compose.yml` or `.env` and recreate it with `docker compose up -d`.

## Automatic Restarts (opt-in)

Off by default. Set `RESTART_MODE` to let the container restart the server on its own:

| `RESTART_MODE` | What happens |
|---|---|
| `off` (default) | No automatic restarts. Use `hy-restart` by hand. |
| `schedule` | Restart every day at `RESTART_TIME`. |
| `on-update` | Check every `RESTART_CHECK_MINUTES` for a new version, and restart when one is available. Only with `VERSION=LATEST`. |

```yaml
environment:
  - RESTART_MODE=schedule
  - RESTART_TIME=04:00        # HH:MM, 24h, in the container time zone
  - TZ=Europe/Paris           # time zone for RESTART_TIME (default UTC)
  - RESTART_WARN_MINUTES=5    # players are warned this long before each restart
```

With `schedule`, the warning starts at `RESTART_TIME` and the restart follows `RESTART_WARN_MINUTES` later.

## The Update Check

On each start with `VERSION=LATEST`:

1. Read the installed version from `HytaleServer.jar`.
2. Skip the check if the last one was less than 1 hour ago (cooldown, stored in `/data/.last-update-check`). `hy-restart` and `FORCE_UPDATE_CHECK=true` skip the cooldown.
3. Ask Hytale for the latest version (`hy-downloader --dry-run`).
4. Download it if it differs from the installed one.

If the check fails (network, login), the server starts with the files it already has.

### Example logs

Up to date:
```
[INFO] Current version: 0.7.7
[INFO] Latest version: 0.7.7
[SUCCESS] Server is up to date
```

Update available:
```
[INFO] Current version: 0.7.6
[INFO] Latest version: 0.7.7
[INFO] Update available: 0.7.6 → 0.7.7
[INFO] Downloading server files (update to v0.7.7)...
```

## Related Settings

- `VERSION`, `PATCHLINE`, `FORCE_DOWNLOAD`, `FORCE_UPDATE_CHECK`: see [Environment Variables](env-variables.md#server-download).
- `RESTART_MODE`, `RESTART_TIME`, `RESTART_WARN_MINUTES`, `RESTART_CHECK_MINUTES`, `TZ`: see [Environment Variables](env-variables.md#automatic-restarts).

## Files

- `/data/HytaleServer.jar`, `/data/Assets.zip`, `/data/HytaleServer.aot`: server files, replaced on update
- `/data/.last-update-check`: time of the last update check (cooldown)

## Troubleshooting

**No update happens:**
- Check that `VERSION=LATEST`.
- Look for `Mode: Update check` and the version lines in `docker logs hytale`.
- Run `docker exec hytale hy-restart --now` to restart and check immediately.

**More detail:** set `LOG_LEVEL=DEBUG` and recreate the container (`docker compose up -d`).
