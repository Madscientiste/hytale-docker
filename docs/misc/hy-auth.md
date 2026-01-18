# hy-auth CLI Specification

## Overview

`hy-auth` is a command-line tool for authenticating with the Hytale server API using OAuth 2.0 Device Code Flow (RFC 8628). It handles the complete authentication flow from device code request through session token generation and credential storage.

## Command Syntax

```
hy-auth [OPTIONS] [OUTPUT_PATH]
```

## Options

### Help and Version

- `-h`, `--help`
  - Display help message and exit
  - Shows usage, description, available options, and examples

- `--version`
  - Display version information and exit
  - Shows script version number

### Output Control

- `-o PATH`, `--output PATH`, `--save-credentials PATH`
  - Specify the output file path for saved credentials
  - Default: `data/auth.json`
  - Supports both `--save-credentials=path` and `--save-credentials path` formats
  - Creates parent directories if they don't exist
  - Validates write permissions before proceeding

### Logging Control

- `-v`, `--verbose`
  - Enable verbose output (DEBUG log level)
  - Shows detailed debug information during authentication flow
  - Overrides `LOG_LEVEL` environment variable

- `-q`, `--quiet`
  - Suppress non-error output (ERROR log level only)
  - Only displays error messages
  - Overrides `LOG_LEVEL` environment variable

### Token Management

- `--refresh [AUTH_FILE]`
  - Refresh existing authentication tokens using stored refresh token
  - If `AUTH_FILE` is not specified, uses default `data/auth.json`
  - Reads refresh token from existing credentials file
  - Updates access token, session token, and identity token
  - Saves updated credentials to the same file
  - Exits after refresh (does not run full authentication flow)

## Positional Arguments

- `OUTPUT_PATH` (optional, deprecated)
  - Legacy positional argument for output file path
  - Use `-o` or `--output` instead
  - If first argument doesn't start with `-`, treat as positional output path for backward compatibility

## Authentication Flow

### Standard Flow (Default)

1. **Request Device Code**
   - POST to device authorization endpoint
   - Receives device code, user code, and verification URI

2. **Display Instructions**
   - Shows verification URI and user code
   - Prompts user to authorize in browser

3. **Poll for Tokens**
   - Polls token endpoint at specified interval
   - Handles `authorization_pending`, `slow_down`, and `expired_token` errors
   - Continues until authorization succeeds or times out

4. **Fetch Profiles**
   - Retrieves available server profiles using access token
   - Selects first available profile

5. **Create Game Session**
   - Creates game session with selected profile
   - Receives session token and identity token

6. **Save Credentials**
   - Writes credentials to specified output file
   - Creates directory structure if needed
   - Validates write permissions

### Refresh Flow (`--refresh`)

1. **Load Existing Credentials**
   - Reads credentials from specified or default auth file
   - Validates file exists and contains refresh token

2. **Refresh Access Token**
   - POST to token endpoint with refresh token grant type
   - Receives new access token and optionally new refresh token

3. **Update Session**
   - Creates new game session with refreshed access token
   - Updates session token and identity token

4. **Save Updated Credentials**
   - Writes updated credentials to same file
   - Preserves existing metadata

## Output Format

Credentials are saved as JSON with the following structure:

```json
{
  "access_token": "string",
  "refresh_token": "string",
  "session_token": "string",
  "identity_token": "string",
  "owner_uuid": "string",
  "owner_name": "string",
  "expires_at": "string"
}
```

## Error Handling

- Invalid arguments: Display error message and exit with code 1
- Missing prerequisites: Check for `curl` (required), warn if `jq` missing
- Network errors: Display descriptive error messages
- Authentication failures: Clear error messages with suggested actions
- File system errors: Permission and path validation with helpful messages
- Token refresh failures: Clear error if refresh token missing or invalid

## Exit Codes

- `0`: Success
- `1`: Error (invalid arguments, authentication failure, file system error, etc.)

## Examples

### Basic Usage

```bash
# Authenticate with default output path
hy-auth

# Authenticate with custom output path
hy-auth --output /path/to/auth.json

# Authenticate with short option
hy-auth -o /path/to/auth.json
```

### Help and Version

```bash
# Show help
hy-auth --help
hy-auth -h

# Show version
hy-auth --version
```

### Logging Control

```bash
# Verbose output
hy-auth --verbose
hy-auth -v

# Quiet mode (errors only)
hy-auth --quiet
hy-auth -q
```

### Token Refresh

```bash
# Refresh using default auth file
hy-auth --refresh

# Refresh using custom auth file
hy-auth --refresh /path/to/auth.json
```

### Combined Options

```bash
# Verbose output with custom path
hy-auth -v -o /custom/path/auth.json

# Quiet refresh
hy-auth --quiet --refresh
```

## Backward Compatibility

- Positional argument support maintained for existing scripts
- If first argument doesn't start with `-`, treat as output path
- Default behavior unchanged when no arguments provided

## Implementation Notes

- POSIX shell compatible (`#!/bin/sh`)
- Uses `_common.sh` for logging functions
- Supports both `jq` and basic shell JSON parsing
- Handles OAuth 2.0 error responses according to RFC 8628
- Validates all inputs before making API calls
- Provides clear, actionable error messages

## Dependencies

- **Required**: `curl` (for HTTP requests)
- **Optional**: `jq` (for robust JSON parsing, falls back to basic parsing if unavailable)

## Environment Variables

- `LOG_LEVEL`: Set default log level (ERROR, WARN, INFO, DEBUG)
  - Overridden by `--verbose` or `--quiet` flags

## API Endpoints

- Device Authorization: `https://oauth.accounts.hytale.com/oauth2/device/auth`
- Token: `https://oauth.accounts.hytale.com/oauth2/token`
- Profiles: `https://account-data.hytale.com/my-account/get-profiles`
- Session: `https://sessions.hytale.com/game-session/new`

## Security Considerations

- Credentials stored in plain JSON (user responsible for file permissions)
- Refresh tokens should be protected
- No credentials logged in verbose mode
- File permissions validated before writing

## Final Notes

I'm still confused on hytale's way of authenticating. The documentation is not very clear and the flow is not very intuitive for me.

But i'll improve it overtime, as security is a concern for me atm.

PRs & Discussions are welcome!