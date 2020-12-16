#! /bin/bash

#   BTRFS snapshot automation script
#   Copyright (C) 2020  xxc3nsoredxx
#
#   This program is free software: you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation, either version 3 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program.  If not, see <http://www.gnu.org/licenses/>.


# Only run as root
if [ $(id -u) -ne 0 ]; then
    echo "Snapshots must be created as root"
    exit -1
fi

declare -A SUBVOLUMES
SRC_SNAPSHOTS=/root/btrfs_snapshots
DEST_SNAPSHOTS=/root/sd_snapshots
SUBVOLUMES=(['/']='root' ['/root']='root_home' ['/home']='home')
NAME=$(date -I)
DESIRED_PREV=$(date -I --date='last saturday')
EXPIRED=$(date -I --date='5 weeks ago')

mount $SRC_SNAPSHOTS
mount $DEST_SNAPSHOTS

for target in ${!SUBVOLUMES[@]}; do
    target_src=$SRC_SNAPSHOTS/${SUBVOLUMES[$target]}
    target_dest=$DEST_SNAPSHOTS/${SUBVOLUMES[$target]}

    # Get the list of snapshots
    list_src=($(ls $target_src))
    list_dest=($(ls $target_dest))

    # If no snapshots exist, make one
    if [ ${#list_src[@]} -eq 0 ]; then
        echo "No existing snapshots found for $target"
        btrfs subvolume snapshot -r $target $target_src/$NAME
        sync
        btrfs send $target_src/$NAME | btrfs receive $target_dest
        sync
        continue
    fi

    src_prev=${list_src[-1]}

    # Check if most recent src snapshot is up to date
    if [[ "$src_prev" < "$DESIRED_PREV" ]]; then
        echo "SRC snapshot '$target_src/$src_prev' is out of date"

        btrfs subvolume snapshot -r $target $target_src/$NAME
        sync
        list_src=(${list_src[@]} $NAME)
        src_prev=$NAME
    fi

    # Check if most recent dest snapshot is up to date
    dest_prev=${list_dest[-1]}

    if [[ "$dest_prev" < "$src_prev" ]]; then
        echo "DEST snapshot '$target_dest/$dest_prev' is out of date"

        # Determine if incremental send is used
        if [ ${#list_src[@]} -ge 2 ]; then
            echo "Previous snapshot of $target is at $target_src/${list_src[-2]}"
            btrfs send -p $target_src/${list_src[-2]} $target_src/${list_src[-1]} | btrfs receive $target_dest
            sync
        else
            echo "No previous snapshot to use as base"
            btrfs send $target_src/${list_src[-1]} | btrfs receive $target_dest
            sync
        fi
        echo "Sending $target_src/${list_src[-1]} complete"

        # Check for expired src snapshots
        # Only delete if there are > 2 snapshots so that incremental send works
        if [ ${#list_src[@]} -gt 2 ]; then
            if [[ "${list_src[0]}" < "$EXPIRED" ]]; then
                echo "Expired snapshot '$target_src/${list_src[0]}'"
                btrfs subvolume delete $target_src/${list_src[0]}
            fi
        else
            echo "Not enough snapshots in '$target_src' to expire"
        fi
    fi
done

umount $DEST_SNAPSHOTS
umount $SRC_SNAPSHOTS
