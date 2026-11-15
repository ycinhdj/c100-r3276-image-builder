# Boot order: microSD and eMMC

The C100 can hold two systems at once: one on the microSD card and one on the
module's 16 GB eMMC. This page explains which one starts and how to choose.

## How the board boots

1. The Tegra boot ROM loads the early bootloader stages and **U-Boot from
   eMMC**. The C100 module has no SPI flash, so the bootloader always lives in
   eMMC, even when the operating system runs from microSD.
2. U-Boot looks for `/boot/extlinux/extlinux.conf` on the first partition of
   each boot device, in order, and starts the first system it finds.

The patched U-Boot from `c100-bootupd` names the storage devices like this:

| U-Boot device | Hardware |
| --- | --- |
| `mmc0` | eMMC (on the module) |
| `mmc1` | microSD slot (SDMMC3 on the C100 carrier) |

The default order is `boot_targets=mmc1 mmc0 usb0 pxe dhcp`, so the **microSD
card comes first**:

| microSD slot | What boots |
| --- | --- |
| Card with a system (`/boot/extlinux/extlinux.conf` on partition 1) | microSD system |
| Empty | eMMC system |
| Data-only card (no `/boot/extlinux`) | eMMC system; the card is skipped |

To see the order on your board, stop U-Boot from the serial console and run
`printenv boot_targets`.

## Booting this image on a board with an eMMC system

Insert the card and power on. The card boots because it comes first. On the
first boot the `c100-bootupd` service:

- reads the bootloader version recorded in the eMMC system
  (`/etc/c100-bootupd.version`) and **skips the update** if it is the same or
  newer;
- otherwise writes the new U-Boot and copies the C100 boot files
  (`nv_boot_control.conf`, the SDMMC3 overlay and `u-boot-preboot.scr`) into the
  eMMC system, then powers off.

The eMMC system and its data are otherwise left alone. Remove the card to start
the eMMC system again.

The updater needs an eMMC `APP` partition to exist. On a blank or erased eMMC
it fails and the card cannot boot; reinstall eMMC first ([EMMC.md](EMMC.md)).

U-Boot also runs `u-boot-preboot.scr` before booting. When a card is missing the
C100 overlays, the script copies them from the eMMC system onto the card, which
is how an unmodified NVIDIA Jetson Nano SD image can start on a C100 that has a
working eMMC system.

## Choosing which system boots

**Remove or insert the card.** Card in: microSD system. Card out: eMMC system.

**Boot eMMC once with the card inserted.** On the serial console (debug UART,
3.3 V USB-serial adapter), press a key during the U-Boot countdown, then:

```text
run bootcmd_mmc0
```

**Make eMMC the default.** On the serial console:

```text
setenv boot_targets "mmc0 mmc1 usb0 pxe dhcp"
saveenv
```

The setting is stored in eMMC. A full eMMC reinstall restores the default
(microSD first). To go back by hand:
`setenv boot_targets "mmc1 mmc0 usb0 pxe dhcp"; saveenv`.

**Use the card for data only.** Format it (ext4 or exFAT) without a
`/boot/extlinux` directory. U-Boot skips it, the eMMC system boots, and Ubuntu
mounts the card as extra storage. This is the usual setup when the system lives
on eMMC.

## Pitfall: both systems use `root=/dev/mmcblk0p1`

Each system's `extlinux.conf` selects its root filesystem with
`root=/dev/mmcblk0p1`. With the C100 overlay, Linux names the **microSD slot
`mmcblk0`**. If you start the eMMC system while a card with a system is
inserted, the kernel can come from eMMC but mount the **card's** root
filesystem.

Avoid it by pointing the eMMC system at its own partition by ID. From the eMMC
system:

```bash
lsblk -o NAME,SIZE,PARTLABEL,PARTUUID   # find the eMMC partition labelled APP
sudo cp /boot/extlinux/extlinux.conf /boot/extlinux/extlinux.conf.bak
sudo sed -i 's#root=/dev/mmcblk[0-9]p1#root=PARTUUID=<APP PARTUUID>#' /boot/extlinux/extlinux.conf
```

Do the same in the microSD system with the card's own PARTUUID if you also want
the card to be independent of device order. Removing the card, or using a
data-only card, avoids the issue entirely.
