#!/bin/env bash

######################################################################
# This script restores a backup make by `livebackup.sh`.
#
# Please make the mandatory changes of the environment variables.
######################################################################

set -o pipefail

source="$1"
targetdev="$2"

confirm() {
    while true
    do
        read -p "Continue (y/n)? " answer
        case "$answer" in
            y|Y) return 0;;
            n|N) return 1;;
        esac
    done
}

image="$source/image.e2i.bz2"
ls "$image"* > /dev/null

size=$(cat "$source/blockdev.size64")
[ $size -gt 0 ] || \
    echo "Warning: Could not get the size of the restoring data!"

echo
echo "Summary"
echo "======="
echo "Source directory: $source"
echo "Target device: $targetdev"
echo "Restore amount: $(($size / 1048576)) MiB"
confirm

echo "Restoring backup ..."
read -s -p "Password: " pass
echo
cat $image* | \
    pass="$pass" scrypt dec --passphrase env:pass - | \
    pbzip2 -d -c | \
    pv -s $size | \
    dd of=$targetdev bs=1M >/dev/null
pass=

echo "Checking restored target device ..."
e2fsck -f $targetdev

echo "Done!"
