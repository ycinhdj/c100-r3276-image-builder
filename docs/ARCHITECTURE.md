# Architecture

The project uses a small command-line entry point and focused shell modules.
Release inputs are pinned, downloaded artifacts are validated, and reusable
build stages are keyed by their inputs.

## Repository layout

```text
build.sh                       command-line entry point
config/release.env             pinned versions, commits, filenames, and URLs
lib/common.sh                  logging, validation, hashing, and state helpers
lib/host.sh                    host dependencies and ARM64 emulation setup
lib/downloads.sh               NVIDIA archive acquisition and validation
lib/upstream.sh                source preparation, U-Boot, and package build
lib/image.sh                   image creation, payload installation, compression
patches/c100-bootupd/           ordered patches for the pinned upstream revision
docs/                          operational documentation
scripts/check.sh               local static checks
scripts/check-upstream-patch.sh upstream patch-series validation
```

## Build pipeline

1. **Host validation** checks architecture, distribution, filesystem features,
   and required commands.
2. **Archive acquisition** downloads the NVIDIA BSP, sample root filesystem,
   source archive, and PCN211181 overlay. Partial downloads are resumable and a
   SHA-256 manifest is generated locally.
3. **Pinned source checkout** resets `c100-bootupd` to the configured commit and
   initializes its U-Boot submodule.
4. **Patch application** applies the ordered repository patch series to the
   pinned upstream checkout.
5. **Jetson Linux preparation** runs the upstream `init-jetpack` flow with
   ARM64 user-mode emulation and binfmt registration.
6. **U-Boot build** resets the submodule to its pinned NVIDIA base and applies
   the C100 U-Boot patches through the upstream Makefile.
7. **Updater package build** creates and signs the eMMC bootloader payload and
   builds the `c100-bootupd` Debian package.
8. **SD image creation** runs NVIDIA's `jetson-disk-image-creator.sh` for the
   Jetson Nano B01 layout.
9. **Payload installation** mounts the APP partition, installs the updater and
   C100 data, enables the required services, and configures the SD root device.
10. **Artifact production** compresses the image and writes SHA-256 checksums.

## Build state

State files are stored in the build workspace. Their keys include source
commits, archive hashes, patch hashes, compiler version, and relevant outputs.
A stage is reused only when its inputs and expected outputs match. Otherwise a
clean workspace is required.

## Upstream patch series

The patch series is applied in filename order:

- `0001-build-system-image-before-signing.patch` ensures the NVIDIA system image
  exists before the signed bootloader package is generated.
- `0002-refresh-gpl-license-reference.patch` keeps the Debian copyright metadata
  valid for current packaging checks.

The CI workflow verifies that the complete series applies to the pinned
`c100-bootupd` commit.
