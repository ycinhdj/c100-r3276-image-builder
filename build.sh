#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=config/release.env
source "$PROJECT_ROOT/config/release.env"
# shellcheck source=lib/common.sh
source "$PROJECT_ROOT/lib/common.sh"
# shellcheck source=lib/host.sh
source "$PROJECT_ROOT/lib/host.sh"
# shellcheck source=lib/downloads.sh
source "$PROJECT_ROOT/lib/downloads.sh"
# shellcheck source=lib/upstream.sh
source "$PROJECT_ROOT/lib/upstream.sh"
# shellcheck source=lib/image.sh
source "$PROJECT_ROOT/lib/image.sh"

DOWNLOAD_DIR="${DOWNLOAD_DIR:-$PROJECT_ROOT/downloads}"
WORK_DIR="${WORK_DIR:-$HOME/.cache/$PROJECT_NAME}"
OUTPUT_DIR="${OUTPUT_DIR:-$PROJECT_ROOT/output}"
JOBS="${JOBS:-$(nproc)}"

INSTALL_DEPS=0
ACCEPT_NVIDIA_LICENSE=0
DOWNLOAD_ONLY=0
PREPARE_ONLY=0
SKIP_DOWNLOAD=0
FORCE_DOWNLOAD=0
CLEAN=0
KEEP_RAW=1

usage() {
    cat <<USAGE
OKdo Nano C100 Jetson Linux image builder $PROJECT_VERSION

Usage:
  bash ./build.sh [options]

Fresh build:
  bash ./build.sh --accept-nvidia-license --install-deps --clean

Options:
  --accept-nvidia-license  Confirm acceptance of NVIDIA's applicable terms.
  --install-deps           Install required Ubuntu packages.
  --download-only          Download and validate release archives, then exit.
  --prepare-only           Prepare the BSP and updater package without an SD image.
  --skip-download          Use local archives without network access.
  --force-download         Redownload all NVIDIA archives.
  --clean                  Recreate the build workspace.
  --no-raw                 Retain only the compressed .img.xz artifact.
  --jobs N                 Set parallel build jobs (default: $JOBS).
  --work-dir PATH          Set the build workspace.
  --downloads PATH         Set the archive directory.
  --output PATH            Set the artifact directory.
  --version                Print the builder version.
  -h, --help               Show this help.
USAGE
}

while (($#)); do
    case "$1" in
        --accept-nvidia-license) ACCEPT_NVIDIA_LICENSE=1 ;;
        --install-deps) INSTALL_DEPS=1 ;;
        --download-only) DOWNLOAD_ONLY=1 ;;
        --prepare-only) PREPARE_ONLY=1 ;;
        --skip-download) SKIP_DOWNLOAD=1 ;;
        --force-download) FORCE_DOWNLOAD=1 ;;
        --clean) CLEAN=1 ;;
        --no-raw) KEEP_RAW=0 ;;
        --jobs)
            need_option_value "$@"
            shift
            JOBS="$1"
            ;;
        --work-dir)
            need_option_value "$@"
            shift
            WORK_DIR="$1"
            ;;
        --downloads)
            need_option_value "$@"
            shift
            DOWNLOAD_DIR="$1"
            ;;
        --output)
            need_option_value "$@"
            shift
            OUTPUT_DIR="$1"
            ;;
        --version)
            printf '%s\n' "$PROJECT_VERSION"
            exit 0
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *) die "Unknown option: $1" ;;
    esac
    shift
done

[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || die "--jobs must be a positive integer."
((SKIP_DOWNLOAD == 0 || FORCE_DOWNLOAD == 0)) || die "--skip-download and --force-download are mutually exclusive."
((SKIP_DOWNLOAD == 0 || DOWNLOAD_ONLY == 0)) || die "--skip-download cannot be combined with --download-only."
((DOWNLOAD_ONLY == 0 || PREPARE_ONLY == 0)) || die "--download-only cannot be combined with --prepare-only."
((FORCE_DOWNLOAD == 0 || ACCEPT_NVIDIA_LICENSE == 1)) || die "--force-download requires --accept-nvidia-license."

verify_host
if ((INSTALL_DEPS)); then
    install_host_dependencies
fi

require_commands curl head stat sha256sum du awk tr readlink
if ((SKIP_DOWNLOAD == 0)); then
    download_archives
fi
validate_archives

if ((DOWNLOAD_ONLY)); then
    log "Download complete"
    printf 'Archives: %s\n' "$DOWNLOAD_DIR"
    exit 0
fi

require_commands \
    git make sudo tar dpkg-deb xz losetup mount umount partprobe mountpoint \
    nproc install find sort cut ln cp python3 aarch64-linux-gnu-gcc

if ((CLEAN)); then
    log "Recreating the build workspace"
    safe_remove_tree "$WORK_DIR"
fi
mkdir -p "$WORK_DIR" "$OUTPUT_DIR"

prepare_arm64_emulator
ensure_arm64_binfmt
initialize_workspace_paths
clone_or_reset_upstream
stage_arm64_emulator
stage_nvidia_archives
prepare_rootfs
build_updater_package

if ((PREPARE_ONLY)); then
    log "Preparation complete"
    printf 'Workspace: %s\n' "$REPO_DIR"
    printf 'Updater package: %s\n' "$DEB_FILE"
    exit 0
fi

create_sd_image

log "Build complete"
printf 'Output directory: %s\n' "$OUTPUT_DIR"
printf 'Compressed image: %s\n' "$XZ_IMAGE"
printf 'Checksum: %s\n' "$XZ_IMAGE.sha256"
