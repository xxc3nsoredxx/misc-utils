#! /bin/bash




echo "arg1: $1" > /tmp/run_test
logger --id=$$ --priority daemon.info --tag ss_crypt "==== arg1: $1 ===="
exit

# Only run as root
if [ $(id -u) -ne 0 ]; then
    echo "Snapshots must be transferred as root"
    exit -1
fi

# Device passed in as arg 1
LUKS_DEVICE=$1

declare -A SUBVOLUMES
SRC_SNAPSHOTS=/root/sd_snapshots
DEST_SNAPSHOTS=/root/snapshot_crypt/mnt
LUKS_KEYFILE=/root/snapshot_crypt/ss_crypt.keyfile.txt
LUKS_UUID='9322092e-1baa-4686-90c0-6bb7d6383d60'
SUBVOLUMES=(['/']='root' ['/root']='root_home' ['/home']='home')

# Oldest snapshot to keep on sd card
OLDEST=$(date -I --date='3 months ago')

NAME=$(date -I)
DESIRED_PREV=$(date -I --date='last saturday')
EXPIRED=$(date -I --date='5 weeks ago')

# Open LUKS cryptfile
cryptsetup --key-file $LUKS_KEYFILE open --type luks $LUKS_DEVICE ss_crypt
mount $DEST_SNAPSHOTS

exit

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
