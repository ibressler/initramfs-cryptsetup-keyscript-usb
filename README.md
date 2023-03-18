# Initramfs cryptsetup keyscript for USB

A custom script to unlock an encrypted [LUKS](https://en.wikipedia.org/wiki/Linux_Unified_Key_Setup) volume using a usb key or mmc storage device.
If the key is missing or the decryption process fails, the script will prompt for the password to type manually.

## Prerequisites

A Linux distribution with an initramfs system.
If you use a complete systemd init you might want to use a [PasswordAgent](https://www.freedesktop.org/wiki/Software/systemd/PasswordAgents/) to achieve the same goal (*no idea how to employ this here*).

## Usage

In contrast to previous versions, an install script `decryptkeydevice_install.sh` was added which automates the manual procedure of setting up the *cryptdevice*. If it is not supplied to the install script its name is derived from `/etc/crypttab` and `cryptsetup status`.

```shell
    sh decryptkeydevice_install.sh /dev/disk/by-id/usb-Generic_Flash_Disk_* [cryptdevice]
```

The install script

1. Adjusts the `/etc/crypttab` accordingly
2. Creates a `decryptkeydevice.hook` in `/etc/initramfs-tools/hooks`
3. Copies the key script and the config file to `/etc/decryptkeydevice/` where `update-initramfs` picks it up on each run for including it in the *initrd* image.
4. Writes random data on the given USB storage device in the unused space between partition table and data partitions (which are aligned typically and thus leaving approx. 1.5 MB unoccupied).
5. Adds a key based on this random data to the *cryptdevice*.


## License
CC-BY-NC-SA 4.0 en

Due to the License of the original source.
May not be nothworthy, because the level of creativity is not high enough or the original authors provided a different license.

## Sources

- https://wiki.ubuntuusers.de/Archiv/System_verschl%C3%BCsseln/Entschl%C3%BCsseln_mit_einem_USB-Schl%C3%BCssel
- https://wejn.org/how-to-make-passwordless-cryptsetup.html
