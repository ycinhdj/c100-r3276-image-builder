# OKdo Nano C100 Jetson Linux R32.7.6 image builder

Build a bootable Jetson Linux R32.7.6 microSD image for the **OKdo Nano C100**
from pinned upstream source revisions and official NVIDIA release archives.

The generated image contains:

- C100 U-Boot support for the SDMMC3 microSD interface;
- the PCN211181 memory overlay;
- C100 boot-control configuration and device-tree overlays;
- a first-boot service that installs the required bootloader content in eMMC;
- SHA-256 checksums for the raw and compressed image artifacts.

NVIDIA binaries are not distributed by this repository. The builder downloads
them from NVIDIA after explicit license acceptance.

## Host requirements

- x86-64 Ubuntu;
- Ubuntu 20.04 for the host configuration recommended by NVIDIA for Jetson
  Linux R32;
- at least 50 GB of free space on a Linux filesystem;
- `sudo` access for package installation, target-rootfs preparation, loop
  devices, mounting, and image creation.

The repository, build workspace, and output directory must be on a filesystem
that supports Unix ownership, permissions, and symbolic links.

## Build an image

```bash
cd c100-r3276-image-builder
bash ./build.sh --accept-nvidia-license --install-deps --clean
```

Run the builder as a normal user. It invokes `sudo` only for operations that
require elevated privileges.

Build artifacts are written to `output/`:

```text
output/
├── c100-jetson-linux-r32.7.6.img
├── c100-jetson-linux-r32.7.6.img.sha256
├── c100-jetson-linux-r32.7.6.img.xz
└── c100-jetson-linux-r32.7.6.img.xz.sha256
```

Verify the compressed artifact:

```bash
cd output
sha256sum -c c100-jetson-linux-r32.7.6.img.xz.sha256
```

Flash `c100-jetson-linux-r32.7.6.img.xz` with a disk-image writer that supports
XZ-compressed images.

## First boot

1. Insert the flashed microSD card into the C100.
2. Power on the board and leave it powered while the bootloader installer runs.
3. Wait until the board powers off completely.
4. Power it on again with the same microSD card inserted.
5. Complete the Ubuntu first-boot setup.

The installer writes the C100 bootloader content required for microSD boot to
eMMC. It does not replace the eMMC root filesystem. The operating system built
by this workflow runs from the microSD card.

See [`docs/EMMC.md`](docs/EMMC.md) for a complete eMMC reinstall through USB
recovery mode.

## Build options

Download and validate the NVIDIA archives:

```bash
bash ./build.sh --accept-nvidia-license --install-deps --download-only
```

Prepare the Jetson Linux tree and updater package without creating an image:

```bash
bash ./build.sh --accept-nvidia-license --install-deps --clean --prepare-only
```

Build from archives already stored in `downloads/`:

```bash
bash ./build.sh --skip-download --clean
```

Keep only the compressed image:

```bash
bash ./build.sh --accept-nvidia-license --install-deps --clean --no-raw
```

Show all command-line options:

```bash
bash ./build.sh --help
```

## Repository structure

Pinned versions, commits, archive names, and URLs are declared in
[`config/release.env`](config/release.env). Build logic is separated into the
modules under [`lib/`](lib/). Source changes required by the pinned
`c100-bootupd` revision are maintained as an ordered patch series under
[`patches/c100-bootupd/`](patches/c100-bootupd/).

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the build design.

## Safety

- Use only with the OKdo Nano C100 / Jetson Nano generation.
- Do not use the generated image on a Jetson Orin device.
- Back up important eMMC data before the first boot.
- Do not interrupt power while bootloader content is being written.
- A complete eMMC flash is destructive and requires USB recovery mode.

## License

The builder is released under the MIT License. NVIDIA archives and upstream
components remain subject to their respective licenses.
