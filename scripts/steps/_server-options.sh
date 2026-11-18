#!/bin/sh
# Hytale server options set from environment variables.
# Sourced after _common.sh by 07-server-options.sh and 09-start-server.sh.
#
# To add a server option, add one line to SERVER_OPTIONS and document the
# variable in docs/env-variables.md (and .env.example). Columns:
#
#   VARIABLE   the environment variable
#   KIND       switch  "true" adds the option, "false" or empty leaves it out
#              value   the option and the variable's value
#              list    the option once per item; items are separated by ";"
#                      or new lines, and spaces around them are removed
#   OPTION     the server option (see: java -jar HytaleServer.jar --help)
#   CHECK      optional: a check_* function below. It gets the value (each
#              item for a list), prints why it is wrong and fails, or passes.
#
# An empty variable leaves its option out, so the server's default applies.
SERVER_OPTIONS='
OWNER_NAME          value   --owner-name
BIND_ADDRESS        value   --bind
TRANSPORT_TYPE      value   --transport
AUTH_MODE           value   --auth-mode      check_auth_mode
UNIVERSE_DIR        value   --universe       check_directory
EXTRA_MODS_DIRS     list    --mods           check_directory
IGNORE_BROKEN_MODS  switch  --ignore-broken-mods
DISABLE_SENTRY      switch  --disable-sentry
SERVER_LOG          value   --log            check_log_levels
BOOT_COMMANDS       list    --boot-command   check_no_comma
'

# Backups: on by default, passed by server_backup_args
ENABLE_BACKUPS="${ENABLE_BACKUPS:-true}"
BACKUP_DIR="${BACKUP_DIR:-/data/backups}"
BACKUP_FREQUENCY="${BACKUP_FREQUENCY:-30}"
BACKUP_MAX_COUNT="${BACKUP_MAX_COUNT:-5}"

# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------

check_auth_mode() {
    case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
        authenticated|offline|insecure) ;;
        *) echo "must be authenticated, offline or insecure, got: $1"; return 1 ;;
    esac
}

# The server needs the folder to exist; it is created when missing
check_directory() {
    case "$1" in
        /*) ;;
        *) echo "must be an absolute path (starting with /), got: $1"; return 1 ;;
    esac
    [ -d "$1" ] && return 0
    mkdir -p "$1" 2>/dev/null || { echo "folder $1 does not exist and cannot be created"; return 1; }
}

# The server splits every value of this option on commas
check_no_comma() {
    case "$1" in
        *,*) echo "cannot contain a comma (the server splits values on commas): $1"; return 1 ;;
    esac
}

# LEVEL or Logger:LEVEL, separated by commas. Levels are Java's
# (java.util.logging), any case, or a number.
check_log_levels() {
    case "$1" in
        *[[:space:]]*) echo "cannot contain spaces, got: $1"; return 1 ;;
    esac
    printf '%s\n' "$1" | tr ',' '\n' | while IFS= read -r item; do
        printf '%s' "$item" | grep -qixE '([^:]+:)?(SEVERE|WARNING|INFO|CONFIG|FINE|FINER|FINEST|ALL|OFF|[0-9]+)' || {
            echo "\"$item\" is not LEVEL or Logger:LEVEL (levels: SEVERE, WARNING, INFO, CONFIG, FINE, FINER, FINEST, ALL, OFF)"
            exit 1
        }
    done
}

# ---------------------------------------------------------------------------
# Building the command line
# ---------------------------------------------------------------------------

# Print $1 quoted for the shell, so `eval "set -- ..."` keeps it one argument
shell_quote() {
    printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

# Print the options from SERVER_OPTIONS, quoted for eval:
#   args=$(server_option_args) || exit 1; eval "set -- $args"
# Options named as arguments are left out. On a wrong value, logs which
# variable and why, and fails.
server_option_args() {
    local skip=" $* "
    printf '%s\n' "$SERVER_OPTIONS" | while read -r var kind option check; do
        [ -n "$var" ] || continue
        case "$skip" in *" $option "*) continue ;; esac
        eval "value=\${$var:-}"
        [ -n "$value" ] || continue
        case "$kind" in
            switch)
                case "$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')" in
                    true) printf '%s ' "$option" ;;
                    false) ;;
                    *) log_error "$var must be true or false, got: $value"; exit 1 ;;
                esac
                ;;
            value)
                if [ -n "$check" ] && ! reason=$($check "$value"); then
                    log_error "$var $reason"; exit 1
                fi
                printf '%s %s ' "$option" "$(shell_quote "$value")"
                ;;
            list)
                # Items come from a pipe: the loop runs in a subshell, so a
                # failure has to be passed on with its exit code
                printf '%s\n' "$value" | tr ';' '\n' | while IFS= read -r item; do
                    item=$(printf '%s' "$item" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
                    [ -n "$item" ] || continue
                    if [ -n "$check" ] && ! reason=$($check "$item"); then
                        log_error "$var $reason"; exit 1
                    fi
                    printf '%s %s ' "$option" "$(shell_quote "$item")"
                done || exit 1
                ;;
            *)
                log_error "Unknown kind \"$kind\" for $var in SERVER_OPTIONS"; exit 1
                ;;
        esac
    done
}

# Print the backup options, quoted for eval. Fails on a relative BACKUP_DIR.
#   server_backup_args          all backup options (none when backups are off)
#   server_backup_args --dir    only --backup-dir, for the world check
server_backup_args() {
    [ "$ENABLE_BACKUPS" = "true" ] || return 0
    case "$BACKUP_DIR" in
        /*) ;;
        *) log_error "BACKUP_DIR must be an absolute path (starting with /), got: $BACKUP_DIR"; return 1 ;;
    esac
    if [ "${1:-}" = "--dir" ]; then
        printf '%s %s ' --backup-dir "$(shell_quote "$BACKUP_DIR")"
        return 0
    fi
    printf '%s %s %s %s %s %s %s ' --backup \
        --backup-dir "$(shell_quote "$BACKUP_DIR")" \
        --backup-frequency "$(shell_quote "$BACKUP_FREQUENCY")" \
        --backup-max-count "$(shell_quote "$BACKUP_MAX_COUNT")"
}

# Print the JVM options (word-split by the caller, as JVM_OPTS always was)
server_jvm_options() {
    local opts="-Xms${INIT_MEMORY:-12G} -Xmx${MAX_MEMORY:-12G}"
    opts="$opts -XX:+UseG1GC"
    opts="$opts -XX:MaxGCPauseMillis=200"
    opts="$opts -XX:+UnlockExperimentalVMOptions"
    opts="$opts -XX:+DisableExplicitGC"
    opts="$opts -XX:+UseStringDeduplication"
    opts="$opts -XX:G1NewSizePercent=30"
    opts="$opts -XX:G1MaxNewSizePercent=40"
    opts="$opts -XX:G1HeapRegionSize=32M"
    opts="$opts -XX:G1ReservePercent=20"
    opts="$opts -XX:InitiatingHeapOccupancyPercent=15"
    opts="$opts -Dfile.encoding=UTF-8"
    opts="$opts --enable-native-access=ALL-UNNAMED"
    [ -n "${JVM_OPTS:-}" ] && opts="$opts $JVM_OPTS"
    [ -n "${JVM_XX_OPTS:-}" ] && opts="$JVM_XX_OPTS $opts"
    # AOT cache, when the download had one: faster startup. If it does not
    # match the jar or the JVM, Java prints a warning and starts without it.
    [ -f /data/HytaleServer.aot ] && opts="-XX:AOTCache=HytaleServer.aot $opts"
    printf '%s\n' "$opts"
}
