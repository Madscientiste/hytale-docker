#!/bin/sh
# Download mods listed in MODS into /data/mods
#
# MODS is a list of download links (.jar or .zip), separated by commas,
# spaces or new lines. A mod is downloaded once; when its file is already in
# /data/mods it is kept as is. Files are never deleted: mods you add by hand
# stay, and a link removed from MODS leaves its file in place (with a warning).

# Get script directory and source common utilities
SCRIPT_DIR=$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")
. "${SCRIPT_DIR}/_common.sh"

MODS_DIR="/data/mods"
MANAGED_LIST="${MODS_DIR}/.mods-from-MODS.txt"   # "<file> <url>" per line

MODS="${MODS:-}"
if [ -z "$(echo "$MODS" | tr -d '[:space:],')" ] && [ ! -s "$MANAGED_LIST" ]; then
    log_debug "MODS is empty, no mods to download"
    exit 0
fi

log_section "Installing Mods"
check_prerequisites curl
mkdir -p "$MODS_DIR" || error_exit "Failed to create $MODS_DIR"

# File name from a link: last path part, without query, with %XX decoded
file_name_from_url() {
    local name
    name=$(printf '%s' "${1%%[?#]*}" | sed 's#.*/##')
    # decode %XX escapes (e.g. %2B -> +, %20 -> space)
    printf '%b' "$(printf '%s' "$name" | sed 's/%\([0-9A-Fa-f][0-9A-Fa-f]\)/\\x\1/g')"
}

NEW_LIST=$(mktemp)
COUNT=0
for url in $(echo "$MODS" | tr ',' ' '); do
    case "$url" in
        https://*|http://*) ;;
        *) error_exit "MODS: not a download link: $url" ;;
    esac

    name=$(file_name_from_url "$url")
    case "$name" in
        [A-Za-z0-9]*.jar|[A-Za-z0-9]*.zip) ;;
        *) name="" ;;
    esac
    case "$name" in
        ""|*[!A-Za-z0-9._+-]*)
            error_exit "MODS: cannot tell the mod file name from $url (expected a link ending in a .jar or .zip file)" ;;
    esac

    echo "$name $url" >> "$NEW_LIST"
    COUNT=$((COUNT + 1))

    if [ -f "${MODS_DIR}/${name}" ]; then
        log_info "Mod present: $name"
        continue
    fi

    log_info "Downloading mod: $name"
    if curl -fsSL --retry 3 --connect-timeout 15 --speed-limit 1024 --speed-time 60 -o "${MODS_DIR}/.${name}.part" "$url"; then
        mv -f "${MODS_DIR}/.${name}.part" "${MODS_DIR}/${name}"
        log_success "Installed mod: $name"
    else
        rm -f "${MODS_DIR}/.${name}.part"
        # Starting without a requested mod could damage worlds that use it
        error_exit "Failed to download mod $name from $url"
    fi
done

# Links that were in MODS before but are not anymore: keep the file and warn on
# every start until the owner deletes it (it may be an old version of a mod)
CURRENT_LIST=$(mktemp)
cp "$NEW_LIST" "$CURRENT_LIST"
if [ -s "$MANAGED_LIST" ]; then
    while read -r old_name old_url; do
        if ! grep -q "^${old_name} " "$CURRENT_LIST" && [ -f "${MODS_DIR}/${old_name}" ]; then
            log_warn "Mod $old_name is no longer in MODS. Its file was kept; delete ${MODS_DIR}/${old_name} if you replaced or removed it."
            echo "$old_name $old_url" >> "$NEW_LIST"
        fi
    done < "$MANAGED_LIST"
fi
rm -f "$CURRENT_LIST"

mv -f "$NEW_LIST" "$MANAGED_LIST"
log_success "Mods ready: ${COUNT} from MODS"
