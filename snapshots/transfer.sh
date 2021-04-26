#! /bin/bash



# Send all output to syslog
exec 1> >(logger --id=$$ --stderr --priority daemon.info --tag ss_crypt_transfer)
exec 2> >(logger --id=$$ --stderr --priority daemon.err --tag ss_crypt_transfer)

# Send message to syslog
# arg1: message
log () {
    echo "$@"
}

# Send error to syslog and abort
# arg1: error message
die () {
    echo "$@" >&2
    exit 1
}

# Only run as root
if [ $(id -u) -ne 0 ]; then
    die "Snapshots can only be transferred as root"
fi

log "Test log"
die "Test error"


declare -A SUBVOLUMES
SRC_SNAPSHOTS=/root/sd_snapshots
DEST_SNAPSHOTS=/root/snapshot_crypt/mnt
LUKS_KEYFILE=/root/snapshot_crypt/ss_crypt.keyfile.txt
# Block device passed in as arg 1
LUKS_DEVICE=$1
LUKS_NAME='ss_crypt'
SUBVOLUMES=(['/']='root' ['/root']='root_home' ['/home']='home')

# Oldest snapshot to keep on sd card
OLDEST=$(date -I --date='3 months ago')

# TODO: delete these
NAME=$(date -I)
DESIRED_PREV=$(date -I --date='last saturday')
EXPIRED=$(date -I --date='5 weeks ago')

# Open LUKS crypt and mount the filesystem inside
cryptsetup --key-file $LUKS_KEYFILE open --type luks $LUKS_DEVICE $LUKS_NAME \
    || die "Failed to open $LUKS_DEVICE as $LUKS_NAME"
log "Opened $LUKS_DEVICE as $LUKS_NAME"
mount $DEST_SNAPSHOTS \
    || die "Failed to mount $LUKS_NAME onto $DEST_SNAPSHOTS"
log "Mounted $LUKS_NAME onto $DEST_SNAPSHOTS"

# Mount the snapshot source
mount $SRC_SNAPSHOTS \
    || die "Failed to mount $SRC_SNAPSHOTS"
log "Mounted $SRC_SNAPSHOTS"

exit

# Loop through the keys of the $SUBVOLUMES map
for target in ${!SUBVOLUMES[@]}; do
    target_src=$SRC_SNAPSHOTS/${SUBVOLUMES[$target]}
    target_dest=$DEST_SNAPSHOTS/${SUBVOLUMES[$target]}

    # Get the list of snapshots
    list_src=($(ls $target_src))
    list_dest=($(ls $target_dest))

    # If no snapshots exist, make one
#    if [ ${#list_src[@]} -eq 0 ]; then
#        echo "No existing snapshots found for $target"
#        btrfs subvolume snapshot -r $target $target_src/$NAME
#        sync
#        btrfs send $target_src/$NAME | btrfs receive $target_dest
#        sync
#        continue
#    fi

    src_prev=${list_src[-1]}

    # Check if most recent src snapshot is up to date
#    if [[ "$src_prev" < "$DESIRED_PREV" ]]; then
#        echo "SRC snapshot '$target_src/$src_prev' is out of date"
#
#        btrfs subvolume snapshot -r $target $target_src/$NAME
#        sync
#        list_src=(${list_src[@]} $NAME)
#        src_prev=$NAME
#    fi

    # Check if most recent dest snapshot is up to date
    dest_prev=${list_dest[-1]}

#    if [[ "$dest_prev" < "$src_prev" ]]; then
#        echo "DEST snapshot '$target_dest/$dest_prev' is out of date"
#
#        # Determine if incremental send is used
#        if [ ${#list_src[@]} -ge 2 ]; then
#            echo "Previous snapshot of $target is at $target_src/${list_src[-2]}"
#            btrfs send -p $target_src/${list_src[-2]} $target_src/${list_src[-1]} | btrfs receive $target_dest
#            sync
#        else
#            echo "No previous snapshot to use as base"
#            btrfs send $target_src/${list_src[-1]} | btrfs receive $target_dest
#            sync
#        fi
#        echo "Sending $target_src/${list_src[-1]} complete"
#
#        # Check for expired src snapshots
#        # Only delete if there are > 2 snapshots so that incremental send works
#        if [ ${#list_src[@]} -gt 2 ]; then
#            if [[ "${list_src[0]}" < "$EXPIRED" ]]; then
#                echo "Expired snapshot '$target_src/${list_src[0]}'"
#                btrfs subvolume delete $target_src/${list_src[0]}
#            fi
#        else
#            echo "Not enough snapshots in '$target_src' to expire"
#        fi
#    fi
done

umount $SRC_SNAPSHOTS \
    || die "Failed to unmount $SRC_SNAPSHOTS"
log "Unmounted $SRC_SNAPSHOTS"

umount $DEST_SNAPSHOTS \
    || die "Failed to unmount $DEST_SNAPSHOTS"
log "Unmounted $DEST_SNAPSHOTS"
cryptsetup close $LUKS_NAME \
    || die "Failed to close $LUKS_NAME"
log "Closed $LUKS_NAME"
