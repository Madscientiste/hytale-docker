# hy-downloader CLI Specification

## Overview

`hy-downloader` is a command-line tool for downloading Hytale server files (HytaleServer.jar and Assets.zip) using authenticated API credentials. It requires a valid `auth.json` file created by `hy-auth` and handles the complete download flow from version selection through file extraction and verification.

## Command Syntax

```
hy-downloader [OPTIONS] --auth-file PATH --output-dir PATH
```

## Options

### Help and Version

- `-h`, `--help`
  - Display help message and exit
  - Shows usage, description, available options, and examples

- `--version`
  - Display version information and exit
  - Shows script version number

### Required Options

- `-a PATH`, `--auth-file PATH`
  - Path to the authentication credentials file (auth.json)
  - This file must be created using `hy-auth` first
  - Must contain a valid `access_token`
  - Path is resolved to absolute path automatically

- `-o PATH`, `--output-dir PATH`
  - Directory where server files will be saved
  - Files are saved with version tags by default:
    - `hs-VERSION.jar` (e.g., `hs-2026.01.15-c04fdfe10.jar`)
    - `ha-VERSION.zip` (e.g., `ha-2026.01.15-c04fdfe10.zip`)
  - Directory is created if it doesn't exist
  - Write permissions are validated before proceeding
  - Path is resolved to absolute path automatically

### Download Control

- `--server-version VERSION`
  - Specify a specific server version to download
  - Default: `LATEST` (downloads the latest available version)
  - Format must be: `YYYY.MM.DD-hash` (e.g., `2026.01.17-4b0f30090`)
  - Partial versions (date only) are not supported
  - If version doesn't exist, returns 404 error with helpful message

- `--patchline PATCHLINE`
  - Specify the patchline to use (e.g., `release`, `beta`)
  - Default: `release`
  - Used when fetching version manifest or constructing download paths

- `-f`, `--force`
  - Force re-download even if files already exist
  - By default, skips download if both files are already present
  - Useful for updating to latest version or re-downloading corrupted files

- `--simple-names`
  - Save files with simple names (`HytaleServer.jar`, `Assets.zip`)
  - Instead of version-tagged names (`hs-VERSION.jar`, `ha-VERSION.zip`)
  - Useful for scripts that expect standard filenames

### Logging Control

- `-v`, `--verbose`
  - Enable verbose output (DEBUG log level)
  - Shows detailed debug information during download
  - Overrides `LOG_LEVEL` environment variable
  - Cannot be used together with `--quiet`

- `-q`, `--quiet`
  - Suppress non-error output (ERROR log level only)
  - Only displays error messages
  - Overrides `LOG_LEVEL` environment variable
  - Cannot be used together with `--verbose`

## Download Flow

### LATEST Version Flow

1. **Get Version Manifest**
   - GET to `/game-assets/version/{patchline}.json` with Bearer token
   - Receives signed manifest URL (expires in 6 hours)

2. **Fetch Manifest Content**
   - GET to signed manifest URL
   - Parses manifest JSON to extract:
     - Version string
     - Download path
     - SHA256 checksum (if available)

3. **Get Signed Download URL**
   - GET to `/game-assets/{download_path}` with Bearer token
   - Receives signed download URL (expires in 6 hours)

4. **Download Game File**
   - Downloads ZIP file to temporary location
   - Shows progress bar during download
   - Displays file size upon completion

5. **Verify SHA256 Checksum**
   - Calculates SHA256 of downloaded file
   - Compares with expected checksum from manifest
   - Fails if checksums don't match

6. **Extract Server Files**
   - Extracts ZIP to temporary directory
   - Locates `HytaleServer.jar` and `Assets.zip`
   - Handles both root-level and `Server/` subdirectory structures

7. **Move to Final Location**
   - Moves files to final output directory
   - Uses version-tagged names (unless `--simple-names` specified)
   - Atomic move operation (files appear only when complete)

8. **Cleanup**
   - Removes temporary files and directories
   - Cleanup runs on exit (including errors)

### Specific Version Flow

1. **Construct Download Path**
   - Builds path: `builds/{patchline}/{version}.zip`
   - No manifest lookup required

2. **Get Signed Download URL**
   - GET to `/game-assets/{download_path}` with Bearer token
   - Returns 404 if version doesn't exist
   - Receives signed download URL

3. **Download and Extract**
   - Same as steps 4-8 from LATEST flow
   - Note: SHA256 verification not available for specific versions

## File Naming

### Default (Version-Tagged)

- `hs-{VERSION}.jar` - HytaleServer.jar with version tag
- `ha-{VERSION}.zip` - Assets.zip with version tag

Example:
- `hs-2026.01.17-4b0f30090.jar`
- `ha-2026.01.17-4b0f30090.zip`

### Simple Names (`--simple-names`)

- `HytaleServer.jar`
- `Assets.zip`

## Error Handling

- Invalid arguments: Display error message and exit with code 1
- Missing prerequisites: Check for `curl` and `unzip` (required), warn if `jq` missing
- Auth file errors: Validates file exists and contains valid `access_token`
- Network errors: Display HTTP status codes and response bodies
- Version errors: Clear messages for invalid format or non-existent versions
- Download errors: Descriptive messages for failed downloads
- Checksum errors: Fail with expected vs actual SHA256 comparison
- File system errors: Permission and path validation with helpful messages
- Extraction errors: Clear messages if required files not found after extraction

## Exit Codes

- `0`: Success
- `1`: Error (invalid arguments, download failure, checksum mismatch, etc.)

## Examples

### Basic Usage

```bash
# Download latest server files
hy-downloader --auth-file ./auth.json --output-dir ./server

# Download with short options
hy-downloader -a ./auth.json -o ./server
```

### Version Selection

```bash
# Download specific version
hy-downloader -a ./auth.json -o ./server --server-version 2026.01.17-4b0f30090

# Download from beta patchline
hy-downloader -a ./auth.json -o ./server --patchline beta
```

### File Naming

```bash
# Use simple names (HytaleServer.jar, Assets.zip)
hy-downloader -a ./auth.json -o ./server --simple-names
```

### Download Control

```bash
# Force re-download even if files exist
hy-downloader -a ./auth.json -o ./server --force

# Force download with short option
hy-downloader -a ./auth.json -o ./server -f
```

### Logging Control

```bash
# Verbose output
hy-downloader -a ./auth.json -o ./server --verbose
hy-downloader -a ./auth.json -o ./server -v

# Quiet mode (errors only)
hy-downloader -a ./auth.json -o ./server --quiet
hy-downloader -a ./auth.json -o ./server -q
```

### Combined Options

```bash
# Download specific version with force and verbose
hy-downloader -a ./auth.json -o ./server \
  --server-version 2026.01.17-4b0f30090 --force -v

# Download latest with simple names and quiet mode
hy-downloader -a ./auth.json -o ./server --simple-names -q
```

## Implementation Notes

- POSIX shell compatible (`#!/bin/bash`)
- Uses embedded logging functions (same as `hy-auth`)
- Supports both `jq` and basic shell JSON parsing (falls back to `python3` or `grep`/`sed`)
- Handles signed URLs with proper URL encoding (`\u0026` → `&`)
- Atomic file operations (downloads to temp, moves when complete)
- Automatic cleanup of temporary files on exit
- Validates all inputs before making API calls
- Provides clear, actionable error messages
- Skips download if files already exist (unless `--force`)

## Dependencies

- **Required**: `curl` (for HTTP requests), `unzip` (for extracting ZIP files)
- **Optional**: `jq` (for robust JSON parsing, falls back to `python3` or basic parsing)

## Environment Variables

- `LOG_LEVEL`: Set default log level (ERROR, WARN, INFO, DEBUG)
  - Overridden by `--verbose` or `--quiet` flags

## API Endpoints

- Version Manifest: `https://account-data.hytale.com/game-assets/version/{patchline}.json`
- Download URL: `https://account-data.hytale.com/game-assets/{download_path}`
- All endpoints require `Authorization: Bearer {access_token}` header

## Security Considerations

- Requires valid authentication credentials from `hy-auth`
- Signed URLs expire after 6 hours
- SHA256 checksum verification for LATEST downloads (when available)
- Temporary files cleaned up automatically
- No credentials logged in verbose mode
- File permissions validated before writing

## Version Format

### Valid Formats

- `LATEST` - Downloads latest available version
- `YYYY.MM.DD-hash` - Full version with hash (e.g., `2026.01.17-4b0f30090`)

### Invalid Formats

- `YYYY.MM.DD` - Partial version (date only, hash required)
- Any other format not matching the patterns above

## File Structure

The downloaded ZIP file contains:
- `HytaleServer.jar` (at root or in `Server/` subdirectory)
- `Assets.zip` (at root or in `Server/` subdirectory)
- Other files (ignored, only JAR and ZIP are extracted)

## Final Notes

The downloader handles both manifest-based (LATEST) and direct path-based (specific version) downloads. For LATEST, it fetches the manifest to get the actual version and download path, while specific versions construct the path directly. SHA256 verification is only available for LATEST downloads since the manifest provides the checksum.

PRs & Discussions are welcome!

> TODO: I should probably move these to python/bun since i got json parsing and other things
