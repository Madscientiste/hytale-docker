# Authentication Guide

## First-Time Setup

When you start the container for the first time, you'll need to authenticate with Hytale using OAuth2 Device Code Flow.

The container will prompt you to:
- Visit a URL and enter a device code
- Complete authentication in your browser
- Credentials will be saved to `/data/auth.json`

## Authentication Flow

The container uses OAuth2 Device Code Flow (RFC 8628) for authentication. Tokens are automatically refreshed when needed, and the container will skip refresh if tokens are still valid to avoid unnecessary API calls.

The authentication process:
1. Sets up the user and group permissions to match your host system
2. Displays the authentication URL and device code
3. Waits for you to complete the OAuth flow in your browser
4. Fetches your Hytale profile and creates a game session
5. Saves credentials to `/data/auth.json` for future use
6. Downloads the latest server files automatically
7. Continues with server configuration and startup

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

## Saved Credentials

After successful authentication, credentials are saved to `/data/auth.json`. This file contains:
- Access token
- Refresh token
- Session token
- Identity token
- Owner UUID and name
- Expiration timestamp

The container will use these saved credentials on subsequent starts, avoiding the need to re-authenticate unless the tokens expire.

## Token Refresh

The container automatically refreshes tokens when needed. If tokens are still valid, the container will skip refresh to avoid unnecessary API calls. Token refresh happens transparently during container startup.

## CLI Tool

For advanced usage and manual authentication, see the [hy-auth.sh documentation](misc/hy-auth.md).

