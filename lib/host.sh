#!/usr/bin/env bash

apt_package_has_candidate() {
    local package="$1" candidate
    candidate="$(apt-cache policy "$package" 2>/dev/null | awk '/Candidate:/ {print $2; exit}')"
    [[ -n "$candidate" && "$candidate" != "(none)" ]]
}

select_qemu_package() {
    local package
    for package in qemu-user-static qemu-user-binfmt qemu-user-binfmt-hwe; do
        if apt_package_has_candidate "$package"; then
            printf '%s\n' "$package"
            return 0
        fi
    done
    return 1
}

install_host_dependencies() {
    local qemu_package

    log "Installing Ubuntu build dependencies"
    sudo apt-get update
    qemu_package="$(select_qemu_package)" || \
        die "No installable ARM64 QEMU user-emulation package was found. Enable Ubuntu Universe and retry."

    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
        bc binfmt-support bison build-essential bzip2 ca-certificates cpio curl \
        crossbuild-essential-arm64 debhelper devscripts device-tree-compiler \
        dosfstools e2fsprogs fakeroot flex gdisk git lbzip2 \
        libncurses-dev libssl-dev libxml2-utils lintian parted pandoc \
        pkg-config python3 python-is-python3 "$qemu_package" rsync \
        sudo u-boot-tools unzip util-linux uuid-runtime xz-utils zlib1g-dev
}

filesystem_type_for_path() {
    local path="$1" existing="$1"
    while [[ ! -e "$existing" ]]; do
        existing="$(dirname -- "$existing")"
    done
    stat -f -c '%T' -- "$existing"
}

require_linux_filesystem() {
    local label="$1" path="$2" fs_type
    fs_type="$(filesystem_type_for_path "$path")"
    case "$fs_type" in
        9p|drvfs|fuseblk|msdos|vfat|exfat|ntfs)
            die "$label must be stored on a Linux filesystem with Unix ownership, permissions, symlinks, and loop-device support. Detected filesystem: $fs_type"
            ;;
    esac
}

verify_host() {
    ((EUID != 0)) || die "Run the builder as a normal user. It invokes sudo only for privileged operations."
    [[ "$(uname -m)" == "x86_64" ]] || die "An x86-64 Ubuntu host is required."
    [[ -r /etc/os-release ]] || die "Cannot identify the host distribution."

    # shellcheck disable=SC1091
    source /etc/os-release
    [[ "${ID:-}" == "ubuntu" ]] || \
        warn "Ubuntu is the supported host distribution; detected ${PRETTY_NAME:-unknown}."
    [[ "${VERSION_ID:-}" == "20.04" ]] || \
        warn "NVIDIA developed Jetson Linux R32 tooling for Ubuntu 20.04; detected ${PRETTY_NAME:-unknown}."

    require_linux_filesystem "Project directory" "$PROJECT_ROOT"
    require_linux_filesystem "Build workspace" "$WORK_DIR"
    require_linux_filesystem "Output directory" "$OUTPUT_DIR"
}

prepare_arm64_emulator() {
    local native_qemu

    QEMU_RUNTIME_DIR="$WORK_DIR/runtime-bin"
    QEMU_RUNTIME_BIN="$QEMU_RUNTIME_DIR/qemu-aarch64-static"

    if command -v qemu-aarch64-static >/dev/null 2>&1; then
        QEMU_SOURCE_BIN="$(command -v qemu-aarch64-static)"
    else
        native_qemu="$(command -v qemu-aarch64 2>/dev/null || true)"
        [[ -n "$native_qemu" ]] || \
            die "No ARM64 QEMU user emulator was found. Install dependencies with --install-deps."
        mkdir -p "$QEMU_RUNTIME_DIR"
        cp -f --reflink=auto "$native_qemu" "$QEMU_RUNTIME_BIN"
        chmod 0755 "$QEMU_RUNTIME_BIN"
        QEMU_SOURCE_BIN="$QEMU_RUNTIME_BIN"
    fi

    [[ -x "$QEMU_SOURCE_BIN" ]] || die "ARM64 QEMU emulator is not executable: $QEMU_SOURCE_BIN"
    ok "ARM64 QEMU emulator: $QEMU_SOURCE_BIN"
}

ensure_arm64_binfmt() {
    sudo systemctl restart systemd-binfmt.service >/dev/null 2>&1 || \
        sudo update-binfmts --enable qemu-aarch64 >/dev/null 2>&1 || true

    if [[ -e /proc/sys/fs/binfmt_misc/qemu-aarch64 || \
          -e /proc/sys/fs/binfmt_misc/qemu-aarch64-static ]]; then
        ok "ARM64 binfmt registration is active"
    else
        warn "ARM64 binfmt registration is not visible; NVIDIA's target-rootfs package installation may fail."
    fi
}
