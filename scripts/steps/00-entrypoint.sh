#!/bin/sh
set -e

# Get script directory and source common utilities
SCRIPT_DIR=$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")
. "${SCRIPT_DIR}/_common.sh"

HYTALE_DATA_DIR="/data"

log_section "Hytale Server Startup"

# Step 1: Check and run authentication if needed
log_step "1" "Authenticating with Hytale"
sh /usr/local/bin/hy-auth.sh -o "${HYTALE_DATA_DIR}/auth.json"

# Step 2: Download server files if needed
log_step "2" "Checking server files"
"${SCRIPT_DIR}/01-download-server.sh"

# Step 3: Configure server from environment variables
log_step "3" "Configuring server"
"${SCRIPT_DIR}/02-configure-server.sh"

# Step 4: Setup RCON plugin
log_step "4" "Setting up RCON plugin"
"${SCRIPT_DIR}/04-setup-rcon.sh"

# Step 5: Load authentication credentials
log_step "5" "Loading authentication credentials"
. "${SCRIPT_DIR}/03-load-auth.sh"

# Step 6: Start server
log_step "6" "Starting Hytale server"
cd "${HYTALE_DATA_DIR}"
"${SCRIPT_DIR}/09-start-server.sh"
