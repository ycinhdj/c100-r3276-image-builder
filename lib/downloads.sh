#!/usr/bin/env bash

has_bzip2_header() {
    local path="$1"
    [[ -f "$path" ]] && [[ "$(head -c 3 "$path" 2>/dev/null || true)" == "BZh" ]]
}

archive_is_valid() {
    local path="$1" minimum_bytes="$2" size
    [[ -f "$path" ]] || return 1
    size="$(stat -c '%s' "$path" 2>/dev/null || printf '0')"
    ((size >= minimum_bytes)) || return 1
    has_bzip2_header "$path"
}

download_archive() {
    local name="$1" url="$2" minimum_bytes="$3"
    local destination partial
    destination="$DOWNLOAD_DIR/$name"
    partial="$destination.part"

    if ((FORCE_DOWNLOAD)); then
        rm -f -- "$destination" "$partial"
    elif archive_is_valid "$destination" "$minimum_bytes"; then
        ok "Archive available: $name ($(du -h "$destination" | awk '{print $1}'))"
        return
    elif [[ -e "$destination" ]]; then
        warn "Removing invalid archive: $destination"
        rm -f -- "$destination"
    fi

    ((ACCEPT_NVIDIA_LICENSE)) || die "The NVIDIA archive '$name' is missing.
Review the NVIDIA terms and rerun with --accept-nvidia-license.

Release: $NVIDIA_RELEASE_PAGE
License: $NVIDIA_LICENSE_PAGE"

    log "Downloading $name"
    curl \
        --location \
        --fail \
        --show-error \
        --retry 5 \
        --retry-delay 3 \
        --retry-connrefused \
        --continue-at - \
        --user-agent "$PROJECT_NAME/$PROJECT_VERSION" \
        --output "$partial" \
        "$url" || die "Download failed for $name. The partial file is retained for the next run."

    if ! archive_is_valid "$partial" "$minimum_bytes"; then
        local preview
        preview="$(head -c 160 "$partial" 2>/dev/null | tr '\r\n' '  ' || true)"
        die "The response for $name is not a valid archive. Response prefix: $preview"
    fi

    mv -f -- "$partial" "$destination"
    ok "Saved: $destination ($(du -h "$destination" | awk '{print $1}'))"
}

download_archives() {
    mkdir -p "$DOWNLOAD_DIR"
    download_archive "$BSP_NAME" "$BSP_URL" "$BSP_MIN_BYTES"
    download_archive "$ROOTFS_NAME" "$ROOTFS_URL" "$ROOTFS_MIN_BYTES"
    download_archive "$SOURCES_NAME" "$SOURCES_URL" "$SOURCES_MIN_BYTES"
    download_archive "$OVERLAY_NAME" "$OVERLAY_URL" "$OVERLAY_MIN_BYTES"
    write_download_manifest
}

resolve_overlay_archive() {
    if archive_is_valid "$DOWNLOAD_DIR/$OVERLAY_NAME" "$OVERLAY_MIN_BYTES"; then
        OVERLAY_SOURCE="$DOWNLOAD_DIR/$OVERLAY_NAME"
    elif archive_is_valid "$DOWNLOAD_DIR/$OVERLAY_ALT_NAME" "$OVERLAY_MIN_BYTES"; then
        OVERLAY_SOURCE="$DOWNLOAD_DIR/$OVERLAY_ALT_NAME"
    else
        die "Missing or invalid PCN211181 overlay in $DOWNLOAD_DIR."
    fi
}

validate_archives() {
    archive_is_valid "$DOWNLOAD_DIR/$BSP_NAME" "$BSP_MIN_BYTES" || \
        die "Missing or invalid archive: $DOWNLOAD_DIR/$BSP_NAME"
    archive_is_valid "$DOWNLOAD_DIR/$ROOTFS_NAME" "$ROOTFS_MIN_BYTES" || \
        die "Missing or invalid archive: $DOWNLOAD_DIR/$ROOTFS_NAME"
    archive_is_valid "$DOWNLOAD_DIR/$SOURCES_NAME" "$SOURCES_MIN_BYTES" || \
        die "Missing or invalid archive: $DOWNLOAD_DIR/$SOURCES_NAME"
    resolve_overlay_archive
}

write_download_manifest() {
    local manifest="$DOWNLOAD_DIR/downloaded-files.sha256" temporary
    resolve_overlay_archive
    temporary="$(mktemp "$DOWNLOAD_DIR/.downloaded-files.sha256.XXXXXX")"
    (
        cd "$DOWNLOAD_DIR" || exit 1
        sha256sum "$BSP_NAME" "$ROOTFS_NAME" "$SOURCES_NAME" "$(basename -- "$OVERLAY_SOURCE")"
    ) > "$temporary"
    mv -f -- "$temporary" "$manifest"
    ok "Archive checksum manifest: $manifest"
}
