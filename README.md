# OKdo Nano C100 Jetson Linux R32.7.6 image builder

One command that builds a bootable **Jetson Linux R32.7.6 (JetPack 4.6.6)**
microSD image for the **OKdo Nano C100**.

This project is built on top of
[**LetsOKdo/c100-bootupd**](https://github.com/LetsOKdo/c100-bootupd), the
original C100 bootloader and image tooling. All of the hard, board-specific work
comes from that repository: the patched U-Boot with SDMMC3 support, the
device-tree overlays, the PCN211181 memory fix and the first-boot bootloader
updater. This builder automates that work and makes it repeatable. See
[Credits](#credits).

## What this adds over the original

The original repository documents a manual workflow: download four NVIDIA
archives by hand, run `init-jetpack`, then `make deb` / `make image`. Its
`make image` target patches the older **JetPack 4.6.1** SD card image (which has
to be downloaded separately) and assumes the image maps to `/dev/mapper/loop0`.

This builder:

- **builds the whole image from R32.7.6.** The image is created with NVIDIA's
  `jetson-disk-image-creator.sh` from the same BSP and root filesystem the
  bootloader is built from, so the bootloader and the OS are the same version;
- **downloads the NVIDIA archives automatically**, with resumable downloads,
  validation and a SHA-256 manifest. You must accept NVIDIA's license with a flag
  before anything is downloaded;
- **pins the upstream commits** (`c100-bootupd` and its U-Boot base) in
  [`config/release.env`](config/release.env);
- **keeps two small fixes as patches** instead of forking the upstream code (see
  [Patches](#patches-to-upstream));
- **caches build stages** (BSP preparation, U-Boot, updater package) based on
  their inputs, so rebuilds are fast and stale results are never reused;
- **uses a free loop device and cleans up mounts** instead of assuming a fixed
  one;
- **outputs a compressed `.img.xz` with checksums**.

NVIDIA binaries are not redistributed. They are downloaded from NVIDIA at build
time.

## Requirements

- An x86-64 Ubuntu host. 20.04 is recommended, since that is NVIDIA's reference
  host for R32.
- At least 50 GB of free space on a Linux filesystem (not NTFS, exFAT or a WSL
  `/mnt/c` path).
- `sudo` access. Run the builder as a normal user; it uses `sudo` only when it
  needs to.

## Build

```bash
git clone https://github.com/ycinhdj/c100-r3276-image-builder.git
cd c100-r3276-image-builder
bash ./build.sh --accept-nvidia-license --install-deps --clean
```

Output in `output/`:

```text
c100-jetson-linux-r32.7.6.img          (omit with --no-raw)
c100-jetson-linux-r32.7.6.img.sha256
c100-jetson-linux-r32.7.6.img.xz
c100-jetson-linux-r32.7.6.img.xz.sha256
```

Flash the `.img.xz` with any image writer that handles XZ (balenaEtcher,
Raspberry Pi Imager, `xzcat … | sudo dd …`).

Other useful options (`bash ./build.sh --help` lists all of them):

| Option | Effect |
| --- | --- |
| `--download-only` | Fetch and validate the NVIDIA archives, then stop. |
| `--skip-download` | Build offline from archives already in `downloads/`. |
| `--prepare-only` | Prepare the BSP and updater package without making an image. |
| `--no-raw` | Keep only the compressed image. |
| `--jobs N`, `--work-dir`, `--downloads`, `--output` | Tune parallelism and paths. |

## First boot

1. Insert the card and power on. A first-boot service writes the C100
   bootloader into eMMC.
2. Wait until the board **powers itself off**. Do not cut power before then.
3. Power on again and complete the Ubuntu setup.

The OS runs from microSD. Only the bootloader content in eMMC is changed. To
completely reinstall eMMC over USB recovery mode, see
[`docs/EMMC.md`](docs/EMMC.md).

> Only for the OKdo Nano C100 / Jetson Nano (T210). Back up eMMC data first.

## How it works

```text
build.sh            entry point and options
config/release.env  pinned versions, commits, archive names and URLs
lib/host.sh         host checks, dependencies, ARM64 emulation (qemu/binfmt)
lib/downloads.sh    NVIDIA archive download and validation
lib/upstream.sh     pinned c100-bootupd checkout, patches, BSP, U-Boot, .deb
lib/image.sh        SD image creation, C100 payload install, compression
patches/            patches applied to the pinned c100-bootupd commit
scripts/check.sh    shellcheck + checks that the patches still apply (used by CI)
```

The pipeline: validate the host, download the archives, check out
`c100-bootupd` at the pinned commit and apply the patches, run its
`init-jetpack`, build the patched U-Boot and the signed `c100-bootupd` package,
create the SD image with NVIDIA's tool, then install the updater, boot-control
config and overlays into the image.

### Patches to upstream

- `0001-build-system-image-before-signing.patch`: generates `system.img`
  before the signing step, which otherwise fails on a fresh tree.
- `0002-refresh-gpl-license-reference.patch`: updates the GPL address in
  `debian/copyright` so current Debian packaging checks pass.

Both are small enough to send upstream.

## Credits

Thanks to the people who did the original work:

- **ZHANG Yuntian ([Radxa](https://radxa.com))**, author of
  [`c100-bootupd`](https://github.com/LetsOKdo/c100-bootupd): the U-Boot
  patches, SDMMC3 and PCN211181 device-tree overlays, the boot-control setup and
  the bootloader updater this image depends on.
- **[OKdo / LetsOKdo](https://github.com/LetsOKdo)**, for publishing and
  maintaining the C100 bootloader project.
- **Adis Veletanlic**, for build fixes contributed to `c100-bootupd`.
- **NVIDIA**, for Jetson Linux and the L4T tools.

## License

The builder scripts are released under the [MIT License](LICENSE).
`c100-bootupd` and the patches in `patches/c100-bootupd/` (which modify it) are
GPL-3.0-or-later. NVIDIA archives remain under NVIDIA's license terms.
