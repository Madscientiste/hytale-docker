#!/bin/sh
# Install the plugins recommended in Hytale's official server manual
#
#   ENABLE_WEBSERVER          Nitrado:WebServer     web server the next two use
#   ENABLE_QUERY              Nitrado:Query         server info and player count over HTTP
#   ENABLE_METRICS            ApexHosting:PrometheusExporter  Prometheus metrics
#   ENABLE_PERFORMANCE_SAVER  Nitrado:PerformanceSaver        lowers load when idle or busy
#
# All on by default. Each release ships one jar per Hytale server version
# (e.g. nitrado-query-1.1.2+0.7.7.jar); the jar matching the installed server
# is downloaded from the plugin's GitHub releases into /data/mods.
#
# The image manages only the files it downloaded (listed in MANAGED_LIST):
# a disabled plugin is moved to /data/.disabled-plugins (outside mods/, so the
# server ignores it), and a jar built for an older server version is replaced.
# A missing build only skips that plugin.

# Get script directory and source common utilities
SCRIPT_DIR=$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")
. "${SCRIPT_DIR}/_common.sh"

MODS_DIR="/data/mods"
MANAGED_LIST="${MODS_DIR}/.recommended-plugins.txt"   # "<key> <file>" per line
DISABLED_DIR="/data/.disabled-plugins"

# key | GitHub repository | jar name prefix | setting
PLUGINS="webserver|nitrado/hytale-plugin-webserver|nitrado-webserver-|ENABLE_WEBSERVER
query|nitrado/hytale-plugin-query|nitrado-query-|ENABLE_QUERY
metrics|apexhosting/hytale-plugin-prometheus|apexhosting-prometheusexporter-|ENABLE_METRICS
performance-saver|nitrado/hytale-plugin-performance-saver|nitrado-performance-saver-|ENABLE_PERFORMANCE_SAVER"

log_section "Installing Recommended Plugins"
check_prerequisites curl jq
mkdir -p "$MODS_DIR" || error_exit "Failed to create $MODS_DIR"
touch "$MANAGED_LIST"

SERVER_VERSION=$(installed_server_version)
if [ -z "$SERVER_VERSION" ]; then
    log_warn "Could not read the server version; recommended plugins are left as they are"
    exit 0
fi

enabled() {
    eval "v=\${$1:-true}"
    [ "$v" = "true" ]
}

managed_file() {
    sed -n "s/^$1 //p" "$MANAGED_LIST" | head -n 1
}

set_managed() {
    local list
    list=$(mktemp)
    grep -v "^$1 " "$MANAGED_LIST" > "$list" || true
    [ -n "$2" ] && echo "$1 $2" >> "$list"
    mv -f "$list" "$MANAGED_LIST"
}

# Direct link to the newest release jar built for $SERVER_VERSION
find_jar_url() {
    curl -fsSL -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/$1/releases?per_page=20" 2>/dev/null \
        | jq -r --arg suffix "+${SERVER_VERSION}.jar" \
            '[.[] | select(.draft | not) | select(.prerelease | not) | .assets[]
              | select(.name | endswith($suffix))][0].browser_download_url // empty'
}

disable_managed() {
    local file="$1" reason="$2"
    if [ -f "${MODS_DIR}/${file}" ]; then
        mkdir -p "$DISABLED_DIR"
        mv -f "${MODS_DIR}/${file}" "${DISABLED_DIR}/${file}"
        log_info "Disabled ${file} (${reason}); moved to ${DISABLED_DIR}"
    fi
}

echo "$PLUGINS" | while IFS='|' read -r key repo prefix setting; do
    current=$(managed_file "$key")

    reason=""
    enabled "$setting" || reason="${setting}=false"
    if [ -z "$reason" ] && { [ "$key" = query ] || [ "$key" = metrics ]; } && ! enabled ENABLE_WEBSERVER; then
        log_warn "$key needs the web server plugin: set ENABLE_WEBSERVER=true, or ${setting}=false"
        reason="needs ENABLE_WEBSERVER=true"
    fi

    if [ -n "$reason" ]; then
        [ -n "$current" ] && disable_managed "$current" "$reason"
        continue
    fi

    # A copy the owner installed by hand wins; do not add a second one
    own=$(ls "$MODS_DIR" 2>/dev/null | grep -E "^${prefix}.*\.(jar|zip)$" | grep -vxF "${current:-/}" | head -n 1)
    if [ -n "$own" ]; then
        log_info "Found ${own} in mods (not installed by this image); leaving ${key} to it"
        continue
    fi

    case "$current" in
        *"+${SERVER_VERSION}.jar")
            if [ -f "${MODS_DIR}/${current}" ]; then
                log_info "Plugin present: ${current}"
                continue
            fi
            if [ -f "${DISABLED_DIR}/${current}" ]; then
                mv -f "${DISABLED_DIR}/${current}" "${MODS_DIR}/${current}"
                log_info "Re-enabled ${current}"
                continue
            fi
            ;;
    esac

    url=$(find_jar_url "$repo")
    if [ -z "$url" ]; then
        log_warn "No ${key} plugin build for server ${SERVER_VERSION} found (https://github.com/${repo}/releases); skipping it"
        [ -n "$current" ] && disable_managed "$current" "built for another server version"
        continue
    fi

    file=$(basename "$url" | sed 's/%2[Bb]/+/g')
    log_info "Downloading ${file}"
    if ! curl -fsSL --retry 3 -o "${MODS_DIR}/.${file}.part" "$url"; then
        rm -f "${MODS_DIR}/.${file}.part"
        log_warn "Failed to download ${file}; skipping ${key}"
        [ -n "$current" ] && disable_managed "$current" "built for another server version"
        continue
    fi
    mv -f "${MODS_DIR}/.${file}.part" "${MODS_DIR}/${file}"

    # Remove the jar this image installed for an older server version
    if [ -n "$current" ] && [ "$current" != "$file" ]; then
        rm -f "${MODS_DIR}/${current}" "${DISABLED_DIR}/${current}"
        log_info "Replaced ${current}"
    fi
    set_managed "$key" "$file"
    log_success "Installed ${file}"
done

log_success "Recommended plugins checked for server ${SERVER_VERSION}"
