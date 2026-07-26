# Full eMMC reinstall

The generated microSD image does not reinstall the eMMC operating system. It
boots a fresh system from microSD and updates only the C100 bootloader-related
content stored in eMMC.

Use the procedure below only when the goal is to erase and replace the complete
eMMC installation.

> **Destructive operation:** all existing eMMC partitions, users, applications,
> and data will be replaced. Create a backup first.

## 1. Prepare the flash workspace

```bash
bash ./build.sh --accept-nvidia-license --install-deps --clean --prepare-only
```

The prepared upstream tree is stored by default at:

```text
~/.cache/c100-r3276-image-builder/src/c100-bootupd
```

## 2. Enter USB recovery mode

Power the C100 off, place the board in Force Recovery Mode, connect its recovery
USB data port to the Ubuntu host, and power it on. Verify that the NVIDIA
recovery device is visible:

```bash
lsusb -d 0955:7f21
```

Do not continue until the device is visible to the Ubuntu environment that will
run the flash command.

## 3. Flash a fresh eMMC system

```bash
cd ~/.cache/c100-r3276-image-builder/src/c100-bootupd
make flash
```

The upstream target invokes NVIDIA's full `flash.sh` flow for
`jetson-nano-emmc`, recreating the eMMC partition layout and installing the
prepared R32.7.6 root filesystem and patched U-Boot.

Do not disconnect power or USB while flashing.

## 4. Install the C100 boot data

After the full flash, interrupt U-Boot from a serial console and expose eMMC as
a USB mass-storage device:

```text
ums 0 0
```

Identify and mount the eMMC APP partition on the Ubuntu host. Replace
`/dev/sdX1` with the device reported by `lsblk`:

```bash
sudo mkdir -p /mnt/c100-emmc
sudo mount /dev/sdX1 /mnt/c100-emmc

cd ~/.cache/c100-r3276-image-builder/src/c100-bootupd
make MNTDIR=/mnt/c100-emmc flash-data

sync
sudo umount /mnt/c100-emmc
```

Return to the serial console, stop USB mass-storage mode, remove the recovery
jumper, and reset the board.

The board should then boot the new R32.7.6 installation from eMMC. The same
patched bootloader also supports the C100 microSD interface.
