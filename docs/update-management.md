# Server Update Management

## Overview

The Hytale server container includes intelligent update checking that automatically keeps your server current while protecting against API spam during rapid container restarts.

## Features

### Smart Update Detection
- ✅ **Version Comparison**: Automatically compares installed version with latest available
- ✅ **Automatic Downloads**: Downloads new versions when `VERSION=LATEST`
- ✅ **Safe Updates**: Only checks during container startup, never while server is running
- ✅ **API Protection**: 1-hour cooldown prevents spam during restart loops

### Flexible Update Control
- ✅ **Automatic Mode**: Default behavior with `VERSION=LATEST`
- ✅ **Manual Mode**: Force immediate checking with `FORCE_UPDATE_CHECK=true`
- ✅ **Pinned Mode**: Disable updates with specific `VERSION` values
- ✅ **Fallback Mode**: Graceful degradation when API is unavailable

## Environment Variables

### `FORCE_UPDATE_CHECK`

**Type:** Boolean  
**Default:** `false`  
**Description:** Force immediate update check, bypassing the 1-hour cooldown. Only applies when `VERSION=LATEST`.

**Usage Scenarios:**
```bash
# Force immediate update check
docker restart hytale-server  # Normal (respects cooldown)
FORCE_UPDATE_CHECK=true docker restart hytale-server  # Immediate (bypasses cooldown)
```

### `VERSION`

Controls whether update checking is enabled:

```bash
# Enable automatic updates (default)
VERSION=LATEST  # Checks for updates during startup

# Pin to specific version (disables update checking)
VERSION=2026.01.17-4b0f30090  # No update checks, always downloads this version
```

## Update Workflow

### Normal Operation

1. **Container Startup** → Download script runs
2. **Version Detection** → Extracts version from existing `HytaleServer.jar`
3. **Cooldown Check** → Respects 1-hour timeout between checks
4. **API Query** → Fetches latest version using `hy-downloader --dry-run`
5. **Version Compare** → Compares current vs latest
6. **Download if Needed** → Only downloads if new version available
7. **Timestamp Update** → Updates `/data/.last-update-check`

### Update Scenarios

#### Scenario 1: Up-to-Date Server
```
[INFO] Checking for server updates...
[INFO] Current version: 2026.01.24-6e2d4fc36
[INFO] Latest version: 2026.01.24-6e2d4fc36
[INFO] Server is up to date
[INFO] Server files already exist. Skipping download.
```

#### Scenario 2: Update Available
```
[INFO] Checking for server updates...
[INFO] Current version: 2026.01.17-4b0f30090
[INFO] Latest version: 2026.01.24-6e2d4fc36
[INFO] New version available: 2026.01.24-6e2d4fc36 (current: 2026.01.17-4b0f30090)
[INFO] Downloading update...
[SUCCESS] Server files downloaded successfully
```

#### Scenario 3: Cooldown Active
```
[DEBUG] Update check skipped: last check was 1800s ago (cooldown: 3600s)
[INFO] Server files already exist. Skipping download.
```

#### Scenario 4: API Failure (Graceful Degradation)
```
[WARN] Failed to get latest version from hy-downloader
[WARN] Failed to check latest version, skipping update check
[INFO] Server files already exist. Skipping download.
```

## Files Created During Updates

### Runtime Files
- `/data/.last-update-check` - Timestamp file (Unix timestamp) for cooldown management
- `/data/HytaleServer.jar` - Server JAR file (updated when new version available)
- `/data/Assets.zip` - Game assets archive (updated when new version available)

### Temporary Files (Cleaned Up)
- `/tmp/auth-copy.json` - Temporary copy of auth credentials for version checking
- `/data/.tmp-download/` - Temporary directory for downloads and extraction

## Best Practices

### Production Updates

**Recommended Workflow:**
```bash
# 1. Force immediate check for latest version
FORCE_UPDATE_CHECK=true docker restart hytale-server

# 2. Monitor logs for update status
docker compose logs -f hytale-server

# 3. Verify update if applied
docker compose exec hytale-server java -jar /data/HytaleServer.jar --version
```

### Development/Testing

**Pin to Specific Version:**
```bash
# Disable automatic updates for testing
VERSION=2026.01.17-4b0f30090 docker restart hytale-server
```

### Recovery Scenarios

**If Update Fails:**
```bash
# Force re-download of current version
FORCE_DOWNLOAD=true docker restart hytale-server

# Or manually specify version to recover
VERSION=2026.01.17-4b0f30090 FORCE_DOWNLOAD=true docker restart hytale-server
```

**If API is Unavailable:**
- Container will continue with existing server files
- Update check will be retried on next container restart (after cooldown)
- No server interruption due to API failures

## Security Considerations

### Auth Token Protection
- Credentials are copied to temporary files during version checks
- Temporary files are cleaned up immediately after use
- Original `/data/auth.json` remains secure

### Update Safety
- Updates only occur during container startup phase
- Never interrupts running server for updates
- Preserves existing configuration and world data

## Troubleshooting

### Common Issues

**Update Check Not Running:**
- Verify `VERSION=LATEST` is set
- Check that both `HytaleServer.jar` and `Assets.zip` exist
- Ensure `/data/auth.json` contains valid credentials

**Update Check Failing:**
- Check auth token expiration: `docker compose exec hytale-server cat /data/auth.json`
- Force token refresh: `FORCE_UPDATE_CHECK=true docker restart hytale-server`
- Verify network connectivity to Hytale API

**Update Stuck in Loop:**
- The 1-hour cooldown prevents rapid API calls
- Set `FORCE_UPDATE_CHECK=true` to bypass cooldown temporarily
- Check logs for API rate limiting or auth issues

### Debug Mode

Enable detailed logging to troubleshoot:
```bash
LOG_LEVEL=DEBUG docker restart hytale-server
```

Debug output includes:
- Cooldown timing information
- Version detection details
- API query responses
- File path resolution

## Integration with Container Lifecycle

The update checking integrates seamlessly with the standard container startup sequence:

1. **Authentication** → Verify/refresh OAuth tokens
2. **Update Check** → Detect and download updates if needed
3. **Configuration** → Apply environment variables to server config
4. **Plugin Setup** → Install and configure RCON
5. **Server Start** → Start updated server with current configuration

This ensures your server always runs the latest version while maintaining stability and avoiding unnecessary API calls.