#!/bin/env bash

set -o pipefail

######################################################################
# This script performs a live backup of the whole root partition.
#
# Please make the mandatory changes of the environment variables.
######################################################################

# NOTE: make sure this directory is not part of the fs in the root
# device
# target="$HOME/mnt/BACKUPS/$(date +%Y%m%d)"
target="$1"
vg="$2"
lv="$3"
partsize="${partsize:-1G}"
snapshot="${snapshot:-snap0}"
loopdev="${loopdev:-/dev/loop10}"
# using ramdisk
#
# NOTE: make sure this file is not part of the fs in the root device
vgextensionfile="${vgextensionfile:-/dev/shm/backuproot-vgext}"
vgextensionsize="${vgextensionsize:-128}"

######################################################################

rootdev="${rootdev:-/dev/$vg/$lv}"

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

readpass() {
    while true
    do
        read -s -p "Password: " pass
        echo
        read -s -p "Retype password: " pass2
        echo
        [ "$pass" = "$pass2" ] && break
        echo "Passwords don't match! Please try again"
    done
    pass2=
}

echo
echo "Summary"
echo "======="
echo "Root device: $rootdev"
echo "Target directory: $target"
confirm

echo "Creating file for LVM extension ..."
if dd if=/dev/zero of="$vgextensionfile" bs=1M count=$vgextensionsize >/dev/null
then
    echo "Setup loop device for LVM extension ..."
    if losetup "$loopdev" "$vgextensionfile" >/dev/null
    then
        echo "Create physical volume for LVM extension ..."
        if pvcreate "$loopdev" >/dev/null
        then
            echo "Extend LVM volume group ..."
            if vgextend "$vg" "$loopdev" >/dev/null
            then
                echo "Creating LVM snapshot ..."
                if lvcreate -l 100%FREE -s -n "$snapshot" "$rootdev" >/dev/null
                then
                    sourcedev="/dev/$vg/$snapshot"

                    echo "Checking source device ..."
                    e2fsck -fn "$sourcedev" >/dev/null 2>/dev/null

                    echo "Preparing the target directory ..."
                    mkdir -p "$target" >/dev/null

                    echo "Saving device information ..."
                    # TODO: check whether device exists
                    size=$(blockdev --getsize64 $sourcedev)
                    # TODO: check available free space
                    fdisk -l "$sourcedev" > "$target/fdisk.info"
                    echo "$size" > "$target/blockdev.size64"

                    echo "Storing backup ..."
                    readpass
                    image="$target/image.e2i.bz2"
                    tmpdir="$(mktemp -d)"
                    pipe="$tmpdir/sha256sum.pipe"
                    mkfifo "$pipe" >/dev/null
                    sha256sum < "$pipe" > "$tmpdir/checksum" & pid=$!
                    if e2image -ra -p "$sourcedev" - | \
                            pbzip2 -1 -c | \
                            pass="$pass" scrypt enc --passphrase env:pass - | \
                            tee "$pipe" | \
                            split -a3 -d -b$partsize - \
                                  "$image"
                    then
                        wait $pid
                        pass=
                        checksum="$(cat $tmpdir/checksum)"

                        echo "Checking the stored data of the new backup ..."
                        if [ "$(cat $image* | sha256sum)" = "$checksum" ]
                        then
                            echo "The checksums match!"
                        else
                            echo "The checksums don't match!"
                            return 1
                        fi
                    fi
                    rm -rf "$tmpdir" >/dev/null

                    echo "Removing LVM snapshot ..."
                    lvremove -y "$sourcedev" >/dev/null
                fi
                echo "Remove LVM volume group extension ..."
                vgreduce "$vg" "$loopdev" >/dev/null
            fi
            echo "Remove physical volume for LVM extension ..."
            pvremove -y "$loopdev" >/dev/null
        fi
        echo "Destroy loop device for LVM extension ..."
        losetup -d "$loopdev" >/dev/null
    fi
    echo "Delete file for LVM extension ..."
    rm "$vgextensionfile" >/dev/null
fi

echo "Done!"
