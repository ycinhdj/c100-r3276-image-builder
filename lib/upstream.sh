#!/usr/bin/env bash

initialize_workspace_paths() {
    SRC_PARENT="$WORK_DIR/src"
    REPO_DIR="$SRC_PARENT/c100-bootupd"
    STATE_DIR="$WORK_DIR/state"
    UPSTREAM_PATCH_DIR="$PROJECT_ROOT/patches/c100-bootupd"
    mapfile -t UPSTREAM_PATCHES < <(find "$UPSTREAM_PATCH_DIR" -maxdepth 1 -type f -name '*.patch' -print | sort)
    ((${#UPSTREAM_PATCHES[@]} > 0)) || die "No upstream patches were found in $UPSTREAM_PATCH_DIR."
    mkdir -p "$SRC_PARENT" "$STATE_DIR"
}

clone_or_reset_upstream() {
    if [[ ! -d "$REPO_DIR/.git" ]]; then
        log "Cloning the pinned C100 bootloader updater"
        git clone --no-checkout "$C100_BOOTUPD_REPOSITORY" "$REPO_DIR"
    fi

    [[ "$(git -C "$REPO_DIR" remote get-url origin)" == "$C100_BOOTUPD_REPOSITORY" ]] || \
        die "Unexpected upstream remote in $REPO_DIR. Use --clean."

    if ! git -C "$REPO_DIR" cat-file -e "$C100_BOOTUPD_COMMIT^{commit}" 2>/dev/null; then
        git -C "$REPO_DIR" fetch --tags origin
    fi
    git -C "$REPO_DIR" reset --hard "$C100_BOOTUPD_COMMIT"
    git -C "$REPO_DIR" submodule sync --recursive

    if [[ -d "$REPO_DIR/u-boot" ]]; then
        git -C "$REPO_DIR/u-boot" am --abort >/dev/null 2>&1 || true
        git -C "$REPO_DIR/u-boot" reset --hard >/dev/null 2>&1 || true
    fi
    git -C "$REPO_DIR" submodule update --init --recursive --checkout

    apply_upstream_patches
}

apply_upstream_patches() {
    local patch
    for patch in "${UPSTREAM_PATCHES[@]}"; do
        git -C "$REPO_DIR" apply --check "$patch" || \
            die "Upstream patch does not apply: $(basename -- "$patch")"
        git -C "$REPO_DIR" apply "$patch"
    done
}

upstream_patch_state_key() {
    sha256sum "${UPSTREAM_PATCHES[@]}" | hash_stream
}

stage_arm64_emulator() {
    local destination="$REPO_DIR/qemu-aarch64-static"
    install -m 0755 "$QEMU_SOURCE_BIN" "$destination"
    ok "Staged ARM64 emulator: $destination"
}

link_or_copy_archive() {
    local source="$1" destination="$2"
    rm -f -- "$destination"
    if ln "$source" "$destination" 2>/dev/null; then
        return
    fi
    cp --reflink=auto "$source" "$destination"
}

stage_nvidia_archives() {
    log "Staging NVIDIA release archives"
    link_or_copy_archive "$DOWNLOAD_DIR/$BSP_NAME" "$REPO_DIR/$BSP_NAME"
    link_or_copy_archive "$DOWNLOAD_DIR/$ROOTFS_NAME" "$REPO_DIR/$ROOTFS_NAME"
    link_or_copy_archive "$DOWNLOAD_DIR/$SOURCES_NAME" "$REPO_DIR/$SOURCES_NAME"
    link_or_copy_archive "$OVERLAY_SOURCE" "$REPO_DIR/$OVERLAY_NAME"
}

rootfs_state_key() {
    {
        printf '%s\n' "$C100_BOOTUPD_COMMIT"
        sha256sum \
            "$DOWNLOAD_DIR/$BSP_NAME" \
            "$DOWNLOAD_DIR/$ROOTFS_NAME" \
            "$DOWNLOAD_DIR/$SOURCES_NAME" \
            "$OVERLAY_SOURCE"
    } | hash_stream
}

prepare_rootfs() {
    local expected marker="$STATE_DIR/rootfs.state"
    expected="$(rootfs_state_key)"

    if [[ -d "$REPO_DIR/Linux_for_Tegra" ]] && state_matches "$marker" "$expected"; then
        log "Reusing the prepared Jetson Linux BSP and root filesystem"
        return
    fi
    [[ ! -e "$REPO_DIR/Linux_for_Tegra" ]] || \
        die "The prepared BSP does not match the current inputs. Rerun with --clean."

    log "Preparing Jetson Linux $JETSON_LINUX_RELEASE"
    chmod +x "$REPO_DIR/init-jetpack"
    (cd "$REPO_DIR" && ./init-jetpack)
    [[ -d "$REPO_DIR/Linux_for_Tegra/rootfs" ]] || die "Jetson Linux root filesystem preparation failed."
    write_state "$marker" "$expected"
}

configure_u_boot_repository() {
    local uboot_dir="$REPO_DIR/u-boot" git_dir
    [[ -d "$uboot_dir" ]] || die "Missing U-Boot submodule: $uboot_dir"

    git -C "$uboot_dir" config user.name "C100 Image Builder"
    git -C "$uboot_dir" config user.email "c100-image-builder@localhost.invalid"

    git_dir="$(git -C "$uboot_dir" rev-parse --git-dir)"
    [[ "$git_dir" == /* ]] || git_dir="$uboot_dir/$git_dir"
    if [[ -d "$git_dir/rebase-apply" ]]; then
        git -C "$uboot_dir" am --abort
    fi
}

u_boot_state_key() {
    local compiler_version
    compiler_version="$(aarch64-linux-gnu-gcc -dumpfullversion -dumpversion)"
    {
        printf '%s\n%s\n' "$UBOOT_BASE_COMMIT" "$compiler_version"
        sha256sum "$REPO_DIR"/patches/*.patch
    } | hash_stream
}

u_boot_outputs_are_valid() {
    local file
    for file in u-boot u-boot.bin u-boot.dtb u-boot-dtb.bin; do
        [[ -s "$REPO_DIR/u-boot/$file" ]] || return 1
    done
}

build_u_boot() {
    local expected marker="$STATE_DIR/u-boot.state" uboot_dir="$REPO_DIR/u-boot"
    expected="$(u_boot_state_key)"

    if u_boot_outputs_are_valid && state_matches "$marker" "$expected"; then
        log "Reusing the patched U-Boot build"
        return
    fi

    configure_u_boot_repository
    git -C "$uboot_dir" am --abort >/dev/null 2>&1 || true
    git -C "$uboot_dir" reset --hard "$UBOOT_BASE_COMMIT"
    git -C "$uboot_dir" clean -fdx

    log "Building the patched C100 U-Boot"
    (cd "$REPO_DIR" && make nproc="$JOBS" build-u-boot)
    u_boot_outputs_are_valid || die "U-Boot build did not produce all required outputs."
    write_state "$marker" "$expected"
}

package_state_key() {
    {
        cat "$STATE_DIR/rootfs.state"
        printf '%s\n' "$(u_boot_state_key)"
        printf '%s\n' "$(upstream_patch_state_key)"
        printf '%s\n' "$C100_BOOTUPD_COMMIT"
    } | hash_stream
}

find_updater_package() {
    find "$SRC_PARENT" -maxdepth 1 -type f -name 'c100-bootupd_*_all.deb' \
        -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n1 | cut -d' ' -f2-
}

updater_package_is_valid() {
    local package="$1" contents
    [[ -n "$package" && -f "$package" ]] || return 1
    [[ "$(dpkg-deb -f "$package" Package 2>/dev/null || true)" == "c100-bootupd" ]] || return 1
    [[ "$(dpkg-deb -f "$package" Version 2>/dev/null || true)" == "$C100_BOOTUPD_VERSION" ]] || return 1
    [[ "$(dpkg-deb -f "$package" Architecture 2>/dev/null || true)" == "all" ]] || return 1
    contents="$(dpkg-deb -c "$package" 2>/dev/null)" || return 1
    grep -Fq './usr/share/c100-bootupd/boot.img.encrypt' <<<"$contents" || return 1
    grep -Fq 'systemd/system/c100-bootupd.service' <<<"$contents"
}

build_updater_package() {
    local expected marker="$STATE_DIR/package.state"
    expected="$(package_state_key)"
    DEB_FILE="$(find_updater_package)"

    if updater_package_is_valid "$DEB_FILE" && state_matches "$marker" "$expected"; then
        log "Reusing the C100 updater package"
        (cd "$REPO_DIR" && make nproc="$JOBS" build-data build-man build-doc)
        return
    fi

    build_u_boot
    log "Building and signing the C100 updater package"
    (
        cd "$REPO_DIR" || exit 1
        make nproc="$JOBS" build-data build-man build-doc replace-u-boot
        make nproc="$JOBS" deb
    )

    DEB_FILE="$(find_updater_package)"
    updater_package_is_valid "$DEB_FILE" || die "The C100 updater package is missing or invalid."
    write_state "$marker" "$expected"
}
