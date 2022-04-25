#!/bin/env bash

set -o pipefail

backupscript=livebackup.sh
restorescript=restore.sh
pvfile=pv.dat
loopdev=/dev/loop1
vg=7383bbcd-baa1-4e3d-a6f8-5d849fbaf946
lv=root
lvsize=200
dest=dest

if mkdir "$dest"
then
    if dd if=/dev/zero of="$pvfile" bs=1M count=$lvsize
    then
        if losetup "$loopdev" "$pvfile"
        then
            if pvcreate "$loopdev"
            then
                if vgcreate "$vg" "$loopdev"
                then
                    if lvcreate -l 100%FREE -n "$lv" "$vg"
                    then
                        targetdev="/dev/$vg/$lv"
                        mkfs.ext4 "$targetdev"
                        mount "$targetdev" mnt/
                        dd if=/dev/random of="mnt/data" bs=1M count=$(($lvsize / 2))
                        umount mnt/



                        partsize=10M vgextensionsize=100 "./$backupscript" "$dest" "$vg" "$lv" && \
                            "./$restorescript" "$dest" "$targetdev"

                        [ -f "$dest/blockdev.size64" ] && \
                            [ -f "$dest/fdisk.info" ]

                        lvremove -y "$targetdev"
                    fi
                    vgremove "$vg"
                fi
                pvremove -y "$loopdev"
            fi
            losetup -d "$loopdev"
        fi
        rm "$pvfile"
    fi
    rm -r "$dest"
fi
