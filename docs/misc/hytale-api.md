# Hytale API Documentation

## Overview

This document describes the Hytale OAuth2 authentication flow and API endpoints for accessing Hytale server resources and game assets.

## Authentication

### OAuth2 Device Code Flow (RFC 8628)

Hytale uses the OAuth2 Device Code Flow for authentication. This flow is suitable for CLI tools and headless servers.

### Client Configuration

- **Client ID**: `hytale-server`
- **Grant Type**: Device Code Flow
- **Scopes**: `openid offline auth:server`

**Note**: The `auth:server` scope provides access to all endpoints including server operations and game asset downloads.

### Endpoints

#### 1. Device Authorization

Request a device code to begin the authentication flow.

**Endpoint**: `POST https://oauth.accounts.hytale.com/oauth2/device/auth`

**Headers**:
```
Content-Type: application/x-www-form-urlencoded
```

**Request Body**:
```
client_id=hytale-server
scope=openid offline auth:server
```

**Response** (200 OK):
```json
{
  "device_code": "abc123...",
  "user_code": "ABCD-1234",
  "verification_uri": "https://oauth.accounts.hytale.com/oauth2/device/verify",
  "verification_uri_complete": "https://oauth.accounts.hytale.com/oauth2/device/verify?user_code=ABCD-1234",
  "expires_in": 1800,
  "interval": 5
}
```

**Fields**:
- `device_code`: Code to poll for token
- `user_code`: Code for user to enter in browser
- `verification_uri`: URL for user to visit
- `verification_uri_complete`: Complete URL with user code
- `expires_in`: Device code expiration time in seconds
- `interval`: Minimum polling interval in seconds

#### 2. Token Exchange

Exchange device code for access token, or refresh an existing token.

**Endpoint**: `POST https://oauth.accounts.hytale.com/oauth2/token`

**Headers**:
```
Content-Type: application/x-www-form-urlencoded
```

**Request Body (Device Code Exchange)**:
```
client_id=hytale-server
grant_type=urn:ietf:params:oauth:grant-type:device_code
device_code=<device_code>
```

**Request Body (Token Refresh)**:
```
client_id=hytale-server
grant_type=refresh_token
refresh_token=<refresh_token>
```

**Response** (200 OK):
```json
{
  "access_token": "eyJhbGciOiJSUzI1NiIs...",
  "refresh_token": "ory_rt_...",
  "expires_in": 3600,
  "token_type": "Bearer"
}
```

**Error Response** (400 Bad Request):
```json
{
  "error": "authorization_pending",
  "error_description": "The authorization request is still pending."
}
```

**Error Codes**:
- `authorization_pending`: User hasn't authorized yet (keep polling)
- `slow_down`: Polling too fast (increase interval)
- `expired_token`: Device code expired
- `access_denied`: User denied authorization

## API Endpoints

All API endpoints require Bearer token authentication.

### Account Endpoints

#### Get User Profiles

Retrieve available profiles for the authenticated user.

**Endpoint**: `GET https://account-data.hytale.com/my-account/get-profiles`

**Headers**:
```
Authorization: Bearer <access_token>
```

**Response** (200 OK):
```json
{
  "owner": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "profiles": [
    {
      "uuid": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
      "username": "exampleuser",
      "entitlements": ["game.base", "game.deluxe", "game.founder"]
    }
  ]
}
```

### Session Endpoints

#### Create Game Session

Create a new game session for a profile.

**Endpoint**: `POST https://sessions.hytale.com/game-session/new`

**Headers**:
```
Authorization: Bearer <access_token>
Content-Type: application/json
```

**Request Body**:
```json
{
  "uuid": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
}
```

**Response** (200 OK):
```json
{
  "sessionToken": "eyJhbGciOiJFZERTQSIs...",
  "identityToken": "eyJhbGciOiJFZERTQSIs...",
  "expiresAt": "2026-01-14T11:51:42.591891503Z"
}
```

**Fields**:
- `sessionToken`: JWT token for game session (EdDSA signed)
- `identityToken`: JWT token with profile information (EdDSA signed)
- `expiresAt`: ISO 8601 timestamp when session expires

### Game Asset Endpoints

#### Get Version Manifest

Get the version manifest for a specific patchline. Returns a signed URL to the manifest file.

**Endpoint**: `GET https://account-data.hytale.com/game-assets/version/{patchline}.json`

**Path Parameters**:
- `patchline`: Patchline identifier (e.g., `release`, `pre-release`)

**Headers**:
```
Authorization: Bearer <access_token>
```

**Response** (200 OK):
```json
{
  "url": "https://ht-game-assets-release....r2.cloudflarestorage.com/version/release.json?X-Amz-Algorithm=AWS4-HMAC-SHA256&..."
}
```

**Response Fields**:
- `url`: Signed URL to Cloudflare R2 storage (valid for 6 hours)

**Fetching the Manifest**:

The signed URL points to a JSON manifest:
```json
{
  "version": "2026.01.13-50e69c385",
  "download_url": "builds/release/2026.01.13-50e69c385.zip",
  "sha256": "bf32f635771ec3839d0bbaa2582ffcfacf689ab49ede48020a8bba8d9f9a3db0"
}
```

**Fields**:
- `version`: Game version string
- `download_url`: Relative path to game build
- `sha256`: SHA256 checksum of the game file

#### Get Signed Download URL

Get a signed URL for downloading a game asset.

**Endpoint**: `GET https://account-data.hytale.com/game-assets/{path}`

**Path Parameters**:
- `path`: Relative path to asset (e.g., `builds/release/2026.01.13-50e69c385.zip`)

**Headers**:
```
Authorization: Bearer <access_token>
```

**Response** (200 OK):
```json
{
  "url": "https://ht-game-assets-release....r2.cloudflarestorage.com/builds/release/2026.01.13-50e69c385.zip?X-Amz-Algorithm=AWS4-HMAC-SHA256&..."
}
```

**Response Fields**:
- `url`: Signed URL to Cloudflare R2 storage (valid for 6 hours)

**Download Flow**:

1. Get version manifest: `GET /game-assets/version/release.json`
2. Fetch manifest from signed URL to get `download_url`
3. Get signed download URL: `GET /game-assets/{download_url}`
4. Download from signed URL
5. Verify SHA256 checksum

## Token Information

### Access Token

The access token is a JWT (JSON Web Token) with the following structure:

**Header**:
```json
{
  "alg": "RS256",
  "kid": "892acd56-3671-412d-8006-7ef41b6a86b4",
  "typ": "JWT"
}
```

**Payload**:
```json
{
  "aud": [],
  "client_id": "hytale-server",
  "exp": 1768391502,
  "iat": 1768387901,
  "iss": "https://oauth.accounts.hytale.com",
  "jti": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "nbf": 1768387901,
  "scp": ["openid", "offline", "auth:server"],
  "sub": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
}
```

**Fields**:
- `scp`: Array of granted scopes
- `sub`: User UUID (subject) - example: `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`
- `exp`: Expiration timestamp
- `iss`: Token issuer

### Refresh Token

Refresh tokens use Ory Hydra format: `ory_rt_...`

They can be used to obtain new access tokens without re-authentication.

### Session Tokens

Session tokens are EdDSA-signed JWTs issued by `https://sessions.hytale.com` with scope `hytale:server`.

## Signed URLs

All game assets are stored on **Cloudflare R2** (S3-compatible storage).

### Signed URL Format

Signed URLs use AWS Signature Version 4 format and include:
- `X-Amz-Algorithm`: `AWS4-HMAC-SHA256`
- `X-Amz-Checksum-Mode`: `ENABLED`
- `X-Amz-Credential`: Access credentials
- `X-Amz-Date`: Request timestamp
- `X-Amz-Expires`: `21600` (6 hours)
- `X-Amz-SignedHeaders`: `host`
- `X-Amz-Signature`: Request signature

### URL Expiration

Signed URLs are valid for **6 hours (21600 seconds)** from generation.

## Error Handling

### HTTP Status Codes

- `200 OK`: Request successful
- `400 Bad Request`: Invalid request (check error response)
- `401 Unauthorized`: Invalid or expired token
- `403 Forbidden`: Insufficient permissions
- `404 Not Found`: Resource not found
- `500 Internal Server Error`: Server error

### Error Response Format

```json
{
  "error": "error_code",
  "error_description": "Human-readable error description"
}
```

## Rate Limiting

No specific rate limiting information is documented. Implement reasonable delays between requests:
- Device code polling: Use the `interval` value from device authorization response
- API requests: Avoid rapid-fire requests

## Security Considerations

1. **Token Storage**: Store tokens securely. Never commit tokens to version control.
2. **Token Refresh**: Always refresh tokens before expiration to avoid service interruption.
3. **HTTPS Only**: All endpoints use HTTPS. Never use HTTP.
4. **Signed URLs**: Signed URLs expire after 6 hours. Regenerate if needed.
5. **Checksum Verification**: Always verify SHA256 checksums after downloading files.

## Implementation Notes

### Single Token for All Operations

The `auth:server` scope provides access to **all endpoints**:
- Account operations (profiles)
- Session operations (game sessions)
- Asset operations (manifests, downloads)

**No need for separate tokens or different scopes.**

### Complete Download Flow

```bash
# 1. Authenticate (use hy-auth.sh or implement device code flow)
# 2. Get version manifest
curl -H "Authorization: Bearer $TOKEN" \
  "https://account-data.hytale.com/game-assets/version/release.json"

# 3. Fetch manifest from signed URL
curl "$SIGNED_MANIFEST_URL"

# 4. Get signed download URL
curl -H "Authorization: Bearer $TOKEN" \
  "https://account-data.hytale.com/game-assets/$DOWNLOAD_PATH"

# 5. Download and verify
curl "$SIGNED_DOWNLOAD_URL" -o game.zip
sha256sum game.zip  # Verify against manifest sha256
```

## References

- [OAuth 2.0 Device Authorization Grant (RFC 8628)](https://tools.ietf.org/html/rfc8628)
- [JSON Web Token (JWT)](https://tools.ietf.org/html/rfc7519)
- [AWS Signature Version 4](https://docs.aws.amazon.com/general/latest/gr/signature-version-4.html)

## See Also

- `scripts/tools/hy-auth.sh` - Implementation of OAuth2 device code flow
- `playground/` - Test scripts and examples (see project root for details)

