#!/bin/sh
# hy-health - Docker health check for the Hytale server
#
# healthy    the server process runs and, when RCON can be used, answers `who`
# unhealthy  the server is not running, does not answer, or startup has taken
#            longer than HEALTH_STARTUP_MINUTES (for example, waiting for a login)
#
# Startup (login, download, configuration) and the first minutes after the
# server starts count as healthy, so updates do not raise false alarms.
#
# Repository: https://github.com/Madscientiste/hytale-docker

. /init-container/_common.sh

STARTUP_MINUTES="${HEALTH_STARTUP_MINUTES:-15}"
BOOT_GRACE_SECONDS=300

[ -f "$HYTALE_STATE_FILE" ] || { echo "no state yet (container starting)"; exit 0; }
read -r state since < "$HYTALE_STATE_FILE"
age=$(( $(date +%s) - ${since:-0} ))

case "$state" in
    starting)
        if [ "$age" -lt $((STARTUP_MINUTES * 60)) ]; then
            echo "starting for ${age}s"
            exit 0
        fi
        echo "startup has taken ${age}s, longer than ${STARTUP_MINUTES} minutes (waiting for a login? see the logs)"
        exit 1
        ;;
    running)
        pid=$(cat "$HYTALE_PID_FILE" 2>/dev/null)
        if [ -z "$pid" ] || [ ! -d "/proc/$pid" ]; then
            echo "server process is not running"
            exit 1
        fi
        if ! rcon_usable; then
            echo "server process is running (no usable RCON password: process check only)"
            exit 0
        fi
        if rcon_command who >/dev/null 2>&1; then
            echo "server answers over RCON"
            exit 0
        fi
        if [ "$age" -lt "$BOOT_GRACE_SECONDS" ]; then
            echo "server booting for ${age}s"
            exit 0
        fi
        echo "server does not answer over RCON"
        exit 1
        ;;
esac

echo "unknown state: $state"
exit 1
