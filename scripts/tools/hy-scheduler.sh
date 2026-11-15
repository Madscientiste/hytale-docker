#!/bin/sh
# hy-scheduler - Background jobs started by the container's supervisor
#
# Automatic restarts (opt-in, RESTART_MODE):
#   off        no automatic restarts (default); use hy-restart by hand
#   schedule   restart every day at RESTART_TIME (HH:MM, container time zone TZ)
#   on-update  restart when a new server version is available (VERSION=LATEST),
#              checked every RESTART_CHECK_MINUTES
# Players are warned RESTART_WARN_MINUTES before each restart (see hy-restart).
#
# Always on: refreshes the Hytale login once a day (AUTH_REFRESH_HOURS) so it
# never expires while the server runs.
#
# Repository: https://github.com/Madscientiste/hytale-docker

. /init-container/_common.sh

AUTH_FILE="/data/auth.json"
RESTART_MODE="${RESTART_MODE:-off}"
RESTART_TIME="${RESTART_TIME:-04:00}"
RESTART_CHECK_MINUTES="${RESTART_CHECK_MINUTES:-60}"

# Refresh the login when the current tokens expire within $1 minutes.
# Uses --refresh, which never falls back to the interactive browser login.
refresh_auth_if_expiring() {
    local within_min="$1" expires_at expires_s now
    expires_at=$(jq -r '.expires_at // empty' "$AUTH_FILE" 2>/dev/null)
    expires_s=$(date -u -d "$(echo "$expires_at" | sed 's/\.[0-9]*Z$/Z/; s/T/ /; s/Z$//')" +%s 2>/dev/null || echo 0)
    now=$(date +%s)
    [ $((expires_s - now)) -gt $((within_min * 60)) ] && return 0
    with_auth_lock sh /usr/local/bin/hy-auth.sh --quiet --refresh "$AUTH_FILE"
}

installed_version() {
    java -jar /data/HytaleServer.jar --version 2>/dev/null | sed -n 's/^HytaleServer v\([^ ]*\).*/\1/p' | tail -n 1
}

latest_version() {
    hy-downloader.sh --auth-file "$AUTH_FILE" --output-dir /tmp --server-version LATEST \
        --patchline "${PATCHLINE:-release}" --dry-run 2>/dev/null | sed -n 's/^Latest version: //p'
}

run_schedule() {
    echo "$RESTART_TIME" | grep -qE '^([01][0-9]|2[0-3]):[0-5][0-9]$' || {
        log_error "RESTART_TIME must be HH:MM (24h), got: $RESTART_TIME. Automatic restarts are off."
        return
    }
    log_info "Automatic restart: every day at ${RESTART_TIME} ($(date +%Z))"
    local last_day=""
    while :; do
        if [ "$(date +%H:%M)" = "$RESTART_TIME" ] && [ "$(date +%F)" != "$last_day" ]; then
            last_day=$(date +%F)
            hy-restart --reason "daily restart" || true
        fi
        sleep 20
    done
}

run_on_update() {
    if [ "${VERSION:-LATEST}" != "LATEST" ]; then
        log_info "Automatic restart on update: off, VERSION is pinned to ${VERSION}"
        return
    fi
    echo "$RESTART_CHECK_MINUTES" | grep -qE '^[0-9]+$' && [ "$RESTART_CHECK_MINUTES" -ge 10 ] || {
        log_error "RESTART_CHECK_MINUTES must be a number of at least 10, got: $RESTART_CHECK_MINUTES. Automatic restarts are off."
        return
    }
    log_info "Automatic restart on update: checking every ${RESTART_CHECK_MINUTES} minutes"
    local current latest
    while :; do
        sleep $((RESTART_CHECK_MINUTES * 60))
        if ! refresh_auth_if_expiring 10 >/dev/null 2>&1; then
            log_warn "Update check skipped: could not refresh the login"
            continue
        fi
        current=$(installed_version)
        latest=$(latest_version)
        if [ -z "$current" ] || [ -z "$latest" ]; then
            log_warn "Update check skipped: could not read the installed or latest version"
        elif [ "$current" != "$latest" ]; then
            log_info "New server version ${latest} available (installed: ${current})"
            hy-restart --reason "update to ${latest}" || true
        else
            log_debug "Update check: ${current} is the latest version"
        fi
    done
}

# Keep the login alive while the server runs. Hytale's refresh token lasts
# 30 days and is renewed on each use; without this, a server running for
# more than 30 days without a restart would need a new browser login.
# Refreshes when auth.json is older than AUTH_REFRESH_HOURS (default 24).
keep_login_fresh() {
    local hours="${AUTH_REFRESH_HOURS:-24}" age
    echo "$hours" | grep -qE '^[0-9]+$' && [ "$hours" -ge 1 ] || hours=24
    while :; do
        sleep 3600
        [ -f "$AUTH_FILE" ] || continue
        age=$(( $(date +%s) - $(stat -c %Y "$AUTH_FILE") ))
        [ "$age" -ge $((hours * 3600)) ] || continue
        if with_auth_lock sh /usr/local/bin/hy-auth.sh --quiet --refresh "$AUTH_FILE" >/dev/null 2>&1; then
            log_info "Login refreshed (keeps the 30-day login alive)"
        else
            log_warn "Login refresh failed; will retry in an hour. If it keeps failing, restart the container and follow the login prompt in its logs"
        fi
    done
}
keep_login_fresh &

case "$RESTART_MODE" in
    off) ;;
    schedule) run_schedule ;;
    on-update) run_on_update ;;
    *) log_error "Unknown RESTART_MODE: $RESTART_MODE (use off, schedule or on-update). Automatic restarts are off." ;;
esac

# Nothing scheduled: stay alive quietly so the supervisor's bookkeeping is simple
while :; do sleep 3600; done
