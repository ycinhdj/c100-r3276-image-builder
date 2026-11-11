#!/usr/bin/env bash

log()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m%s\033[0m\n' "$*"; }
warn() { printf '\n\033[1;33mWARNING: %s\033[0m\n' "$*" >&2; }
die()  { printf '\n\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

require_commands() {
    local command_name
    for command_name in "$@"; do
        command -v "$command_name" >/dev/null 2>&1 || \
            die "Missing command: $command_name. Install dependencies with --install-deps."
    done
}

need_option_value() {
    [[ $# -ge 2 && -n "$2" ]] || die "Missing value after $1"
}

safe_remove_tree() {
    local path resolved
    path="$1"
    resolved="$(readlink -m -- "$path")"
    case "$resolved" in
        /|/home|/root|"$HOME") die "Refusing to remove unsafe path: $resolved" ;;
    esac
    sudo rm -rf --one-file-system -- "$resolved"
}

write_state() {
    local destination="$1" value="$2" temporary
    mkdir -p "$(dirname -- "$destination")"
    temporary="$(mktemp "${destination}.XXXXXX")"
    printf '%s\n' "$value" > "$temporary"
    mv -f -- "$temporary" "$destination"
}

state_matches() {
    local path="$1" expected="$2"
    [[ -f "$path" ]] && [[ "$(cat -- "$path")" == "$expected" ]]
}

hash_stream() {
    sha256sum | awk '{print $1}'
}

utc_timestamp() {
    local epoch="${SOURCE_DATE_EPOCH:-}"
    if [[ -n "$epoch" ]]; then
        date -u -d "@$epoch" +'%Y-%m-%dT%H:%M:%SZ'
    else
        date -u +'%Y-%m-%dT%H:%M:%SZ'
    fi
}
