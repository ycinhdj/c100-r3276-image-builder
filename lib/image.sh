#!/usr/bin/env bash

LOOP_DEVICE=""
MOUNT_DIR=""

cleanup_image_mount() {
    if [[ -n "$MOUNT_DIR" ]] && mountpoint -q "$MOUNT_DIR"; then
        sudo umount "$MOUNT_DIR" || true
    fi
    if [[ -n "$MOUNT_DIR" && -d "$MOUNT_DIR" ]]; then
        rmdir "$MOUNT_DIR" 2>/dev/null || true
    fi
    if [[ -n "$LOOP_DEVICE" ]]; then
        sudo losetup -d "$LOOP_DEVICE" 2>/dev/null || true
    fi
}

wait_for_app_partition() {
    local partition="${LOOP_DEVICE}p1"
    for _ in {1..20}; do
        [[ -b "$partition" ]] && return
        sudo partprobe "$LOOP_DEVICE" >/dev/null 2>&1 || true
        sleep 0.25
    done
    die "The APP partition did not appear: $partition"
}

install_c100_payload() {
    local root="$1" extlinux
    extlinux="$root/boot/extlinux/extlinux.conf"

    sudo dpkg-deb -x "$DEB_FILE" "$root"

    sudo mkdir -p \
        "$root/etc/systemd/system/multi-user.target.wants" \
        "$root/etc/systemd/system/nv-oem-config.target.wants" \
        "$root/usr/local/share"

    sudo ln -sfn /lib/systemd/system/c100-bootupd.service \
        "$root/etc/systemd/system/multi-user.target.wants/c100-bootupd.service"
    sudo ln -sfn /lib/systemd/system/c100-bootupd_oem.service \
        "$root/etc/systemd/system/nv-oem-config.target.wants/c100-bootupd_oem.service"

    sudo install -m 0644 "$REPO_DIR/data/nv_boot_control.conf" "$root/etc/nv_boot_control.conf"
    sudo install -m 0644 "$REPO_DIR/data/nv_boot_control.conf" "$root/usr/local/share/nv_boot_control.conf"
    sudo install -m 0644 "$REPO_DIR/data/nv_boot_control.service" "$root/etc/systemd/system/nv_boot_control.service"
    sudo ln -sfn ../nv_boot_control.service \
        "$root/etc/systemd/system/nv-oem-config.target.wants/nv_boot_control.service"
    sudo install -m 0644 "$REPO_DIR/data/tegra210-p3448-common-sdmmc3.dtbo" \
        "$root/boot/tegra210-p3448-common-sdmmc3.dtbo"
    sudo install -m 0644 "$REPO_DIR/data/tegra210-porg-p3448-emc-a00.dtbo" \
        "$root/boot/tegra210-porg-p3448-emc-a00.dtbo"
    sudo install -m 0644 "$REPO_DIR/data/u-boot-preboot.scr" "$root/u-boot-preboot.scr"

    [[ -f "$extlinux" ]] || die "Generated image has no extlinux configuration."
    if grep -Eq 'root=/dev/mmcblk[0-9]+p[0-9]+' "$extlinux"; then
        sudo sed -E -i 's#root=/dev/mmcblk[0-9]+p[0-9]+#root=/dev/mmcblk0p1#g' "$extlinux"
    elif ! grep -q 'root=/dev/mmcblk0p1' "$extlinux"; then
        warn "No explicit MMC root device was found in extlinux.conf."
    fi

    sudo tee "$root/etc/c100-image-release" >/dev/null <<META
IMAGE_NAME=$IMAGE_NAME
JETSON_LINUX=$JETSON_LINUX_RELEASE
JETPACK=$JETPACK_RELEASE
C100_BOOTUPD=$C100_BOOTUPD_VERSION
UPSTREAM_COMMIT=$C100_BOOTUPD_COMMIT
BUILDER_VERSION=$PROJECT_VERSION
BUILD_TIME_UTC=$(utc_timestamp)
META
}

create_sd_image() {
    RAW_IMAGE="$OUTPUT_DIR/$IMAGE_NAME"
    XZ_IMAGE="$RAW_IMAGE.xz"
    rm -f -- "$RAW_IMAGE" "$XZ_IMAGE" "$RAW_IMAGE.sha256" "$XZ_IMAGE.sha256"

    log "Creating the Jetson Linux microSD image"
    (
        cd "$REPO_DIR/Linux_for_Tegra" || exit 1
        sudo env ROOTFS_DIR="$REPO_DIR/Linux_for_Tegra/rootfs" \
            ./tools/jetson-disk-image-creator.sh \
            -o "$RAW_IMAGE" \
            -b jetson-nano \
            -r 300
    )
    sudo chown "$(id -u):$(id -g)" "$RAW_IMAGE"
    [[ -s "$RAW_IMAGE" ]] || die "Image creation did not produce $RAW_IMAGE"

    trap cleanup_image_mount EXIT
    log "Installing the C100 bootloader updater into the image"
    LOOP_DEVICE="$(sudo losetup --find --show --partscan "$RAW_IMAGE")"
    wait_for_app_partition
    MOUNT_DIR="$(mktemp -d)"
    sudo mount "${LOOP_DEVICE}p1" "$MOUNT_DIR"
    install_c100_payload "$MOUNT_DIR"
    sync
    cleanup_image_mount
    LOOP_DEVICE=""
    MOUNT_DIR=""
    trap - EXIT

    log "Compressing and checksumming the image"
    xz -T0 -6 --keep "$RAW_IMAGE"
    (
        cd "$OUTPUT_DIR" || exit 1
        sha256sum "$IMAGE_NAME" > "$IMAGE_NAME.sha256"
        sha256sum "$IMAGE_NAME.xz" > "$IMAGE_NAME.xz.sha256"
    )

    if ((KEEP_RAW == 0)); then
        rm -f -- "$RAW_IMAGE"
    fi

    [[ -s "$XZ_IMAGE" && -s "$XZ_IMAGE.sha256" ]] || die "Compressed image output is incomplete."
}
