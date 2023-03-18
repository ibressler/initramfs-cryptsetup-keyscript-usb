#!/bin/sh

# get the script directory before creating any files
scriptdir="$(dirname "$(readlink -f "$0")")"
conf="$(ls "$scriptdir"/*.conf)"

if [ ! -f "$conf" ]; then
    echo "Config file '$conf' not found! Giving up."
    exit 1
fi

keydev="$1"
if [ ! -b "$keydev" ]; then
    echo "Provided path '$keydev' is not a block device, giving up!"
    echo "Please provide an existing block device as first argument for storing the key."
    exit 1
fi

# find the device name of the crypted and mapped device
crypttab="/etc/crypttab"
mappeddev="$(basename "$2")"
if [ ! -z "$mappeddev" ] && ! grep -q "^$mappeddev" "$crypttab"; then
    echo "Provided mapped device '$mappeddev' is not in '$crypttab'!"
    echo "Please provide an existing mapped dev or omit it to be determined from $crypttab."
    exit 1
fi
if [ -z "$mappeddev" ]; then
    mappeddev="$(awk '/^[^#]+$/ {print $1}' "$crypttab")"
fi
cryptdev="$(sudo cryptsetup status "$mappeddev" | awk '/device/{print $NF}')"
if [ ! -b "$cryptdev" ]; then
    echo "Could not determine the crypted and mapped dev from $crypttab! Giving up."
    exit 1
fi
echo "Using mapped dev '$mappeddev' and cryptdev '$cryptdev'."

# adjust crypttab accordingly
targetdir="/etc/decryptkeydevice"
keyscript="$targetdir/$(basename "$(ls "$scriptdir"/*keyscript.sh)")"
#cryptdev_escaped="$(echo "$cryptdev" | awk '{gsub("/","\/");print}')"
#echo "cryptdev_escaped $cryptdev_escaped"
sudo sed -i -e "s#^\($mappeddev\)\s\([^ ]\+\).*\$#\1 \2 none luks,keyscript=$keyscript#" "$crypttab"
echo "Updated $crypttab:"
cat "$crypttab"

# arrange the script being picked up when initramfs is built
hookfn="/etc/initramfs-tools/hooks/decryptkeydevice.hook"
keyscript="$(ls "$scriptdir"/*keyscript.sh)"
hooktmp="$(mktemp)"
cat > "$hooktmp" <<EOF
#!/bin/sh
# initramfs hook to copy the keyscript and its config into the ramfs

mkdir -p \$DESTDIR$targetdir
cp -p '$keyscript' '$conf' \$DESTDIR$targetdir/
EOF

sudo mv "$hooktmp" "$hookfn"
sudo chmod +x "$hookfn"
echo "Created initramfs hook '$hookfn':"
cat "$hookfn"

exit

# determine available key space on provided disk,
# read partition table boundaries and where the partitions start
boundaries="$(sudo gdisk -l "$keydev" | awk '
    /First usable/ { match($0,"[0-9]+"); start=substr($0,RSTART,RLENGTH) }
    /^ +1/ { end=$2 -1 }
    /Sector size/ { split($(NF-1),secbytes,"/") }
    END { print "SEC_START="start";SEC_END="end";SEC_BYTES="secbytes[1]";" }')"
echo $boundaries
eval $boundaries
. "$conf"
sed -i "/DECRYPTKEYDEVICE_DISKID/s#=.*\$#='$(basename $keydev)'#" "$conf"
sed -i "/DECRYPTKEYDEVICE_BLOCKSIZE/s/=.*\$/='$SEC_BYTES'/" "$conf"
if [ "$DECRYPTKEYDEVICE_SKIPBLOCKS" -lt "$SEC_START" ]; then
    sed -i "/DECRYPTKEYDEVICE_SKIPBLOCKS/s/=.*\$/='$SEC_START'/" "$conf"
fi
. "$conf"
echo "DECRYPTKEYDEVICE_READBLOCKS: $DECRYPTKEYDEVICE_READBLOCKS"

if [ "$((DECRYPTKEYDEVICE_SKIPBLOCKS+DECRYPTKEYDEVICE_READBLOCKS))" -ge "$SEC_END" ]; then
    echo "Not enough space for $DECRYPTKEYDEVICE_READBLOCKS blocks in free area from $DECRYPTKEYDEVICE_SKIPBLOCKS to $SEC_END after the partition table! Giving up."
    exit 1
fi

# fill the space with random data
cmd_dd="dd if=/dev/urandom of='$keydev' bs='$SEC_BYTES' seek='$SEC_START' count='$((SEC_END-SEC_START))'"
read -p "Write random data to from sector $SEC_START to $SEC_END on $keydev? (Ctrl-C to abort)" _
echo $cmd_dd
eval "sudo $cmd_dd"

cmd_crypt="cryptsetup luksAddKey --new-keyfile-offset '$((DECRYPTKEYDEVICE_SKIPBLOCKS*DECRYPTKEYDEVICE_BLOCKSIZE))' --new-keyfile-size '$((DECRYPTKEYDEVICE_READBLOCKS*DECRYPTKEYDEVICE_BLOCKSIZE))' '$cryptdev' '$keydev'"
echo $cmd_crypt
eval "sudo $cmd_crypt"

echo DONE
