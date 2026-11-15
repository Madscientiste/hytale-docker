#!/bin/sh
# rcon-cli - send a console command to the Hytale server over RCON
#
#   docker exec hytale rcon-cli who
#   docker exec hytale rcon-cli say "Hello"
#   docker exec -it hytale rcon-cli          # interactive console
#
# Wraps itzg/rcon-cli: connects to this container's RCON server and uses the
# plaintext RCON_PASSWORD, or the password the image generated in
# /data/.rcon-password. Flags you pass (--host, --port, --password) still win.
#
# Repository: https://github.com/Madscientiste/hytale-docker

. /init-container/_common.sh

if password=$(rcon_plain_password 2>/dev/null); then
    export RCON_PASSWORD="$password"
else
    # Only a hash is known: rcon-cli would send the hash, which never works
    unset RCON_PASSWORD
fi
# RCON_HOST is the address the plugin listens on (often 0.0.0.0); connect locally
export RCON_HOST=127.0.0.1
export RCON_PORT="${RCON_PORT:-25575}"

exec /usr/local/lib/rcon-cli/rcon-cli "$@"
