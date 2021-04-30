#! /bin/bash


declare -A SUBVOLUMES
SRC_SNAPSHOTS=/root/sd_snapshots
DEST_SNAPSHOTS=/root/snapshot_crypt/mnt
LUKS_KEYFILE=/root/snapshot_crypt/ss_crypt.keyfile.txt
# udev creates a symlink /dev/ss_crypt pointing to the partition
LUKS_DEVICE=/dev/ss_crypt
LUKS_NAME=ss_crypt
SUBVOLUMES=(['/']='root' ['/root']='root_home' ['/home']='home')

# Oldest snapshot to keep on sd card
OLDEST=$(date -I --date='3 months ago')

# TODO: delete these
NAME=$(date -I)
DESIRED_PREV=$(date -I --date='last saturday')
EXPIRED=$(date -I --date='5 weeks ago')

# Flags to control what is cleaned up
LUKS_OPENED=0
LUKS_MOUNTED=0
SRC_MOUNTED=0
# cryptsetup(8) exit codes
CRYPT_SUCCESS=0
CRYPT_EXISTS_BUSY=5

# Ensure the variables used for log file descriptors are unused
unset LOG_INFO
unset LOG_ERR

# Ensure the variable used to hold exit codes is unused
unset STATUS

# Close LUKS and unmount if needed
# Only close/unmount the ones opened/mounted by the script
cleanup () {
    if [ $SRC_MOUNTED -eq 1 ]; then
        umount $SRC_SNAPSHOTS \
            || die "Failed to unmount $SRC_SNAPSHOTS"
        log "Unmounted $SRC_SNAPSHOTS"
        sleep 0.1
    fi

    if [ $LUKS_MOUNTED -eq 1 ]; then
        umount $DEST_SNAPSHOTS \
            || die "Failed to unmount $DEST_SNAPSHOTS"
        log "Unmounted $DEST_SNAPSHOTS"
        sleep 0.1
    fi

    if [ $LUKS_OPENED -eq 1 ]; then
        # Attempt to close LUKS device. If busy, wait a bit and retry a few
        # times. Error if all unsuccessful.
        for i in {1..3}; do
            log "Attempt $i to close $LUKS_NAME"
            cryptsetup close $LUKS_NAME
            STATUS=$?

            if [ $STATUS -eq $CRYPT_EXISTS_BUSY ]; then
                sleep 0.1
            elif [ $STATUS -eq $CRYPT_SUCCESS ]; then
                log "Closed $LUKS_NAME"
                break
            else
                die "Failed to close $LUKS_NAME"
            fi
        done

        if [ $STATUS -ne $CRYPT_SUCCESS ]; then
            die "Failed to close $LUKS_NAME"
        fi
    fi
}

# Send message to syslog
# arg1: message
log () {
    echo "$@"
    echo "$@" >&$LOG_INFO
}

# Send error to syslog and abort
# arg1: error message
die () {
    echo "$@" >&2
    echo "$@" >&$LOG_ERR
    exit 1
}

# Create file descriptors for syslog info and syslog err
exec {LOG_INFO}> >(logger --id=$$ --priority daemon.info --tag ss_crypt_transfer)
exec {LOG_ERR}> >(logger --id=$$ --priority daemon.err --tag ss_crypt_transfer)

# Install exit handler
trap cleanup EXIT

# Only run as root
if [ $(id -u) -ne 0 ]; then
    die "Snapshots can only be transferred as root"
fi

# Only run if udev's symlink exists
if [ ! -e $LUKS_DEVICE ]; then
    die "$LUKS_DEVICE not found"
fi

# Open LUKS crypt
cryptsetup --key-file $LUKS_KEYFILE open --type luks $LUKS_DEVICE $LUKS_NAME
STATUS=$?
if [ $STATUS -eq $CRYPT_SUCCESS ]; then
    log "Opened $LUKS_DEVICE as $LUKS_NAME"
    LUKS_OPENED=1
elif [ $STATUS -eq $CRYPT_EXISTS_BUSY ]; then
    log "$LUKS_NAME already opened"
else
    die "Failed to open $LUKS_DEVICE as $LUKS_NAME"
fi

# Mount the filesystem in the crypt
if ! (findmnt $DEST_SNAPSHOTS &> /dev/null); then
    if (mount $DEST_SNAPSHOTS &> /dev/null); then
        log "Mounted $LUKS_NAME onto $DEST_SNAPSHOTS"
        LUKS_MOUNTED=1
    else
        die "Failed to mount $LUKS_NAME onto $DEST_SNAPSHOTS"
    fi
else
    log "$DEST_SNAPSHOTS already mounted"
fi

# Mount the snapshot source
if ! (findmnt $SRC_SNAPSHOTS &> /dev/null); then
    if (mount $SRC_SNAPSHOTS &> /dev/null); then
        log "Mounted $SRC_SNAPSHOTS"
        SRC_MOUNTED=1
    else
        die "Failed to mount $SRC_SNAPSHOTS"
    fi
else
    log "$SRC_SNAPSHOTS already mounted"
fi

log "Transfer cutoff: $OLDEST"
# Loop through the keys of the $SUBVOLUMES map
for target in ${!SUBVOLUMES[@]}; do
    log "'$target' snapshots:"

    target_src=$SRC_SNAPSHOTS/${SUBVOLUMES[$target]}
    target_dest=$DEST_SNAPSHOTS/${SUBVOLUMES[$target]}

    # Get the list of snapshots
    list_src=($(ls $target_src))
    list_dest=($(ls $target_dest))

    # Get the most recent snapshot on the destination drive to use as a base
    dest_prev=''
    if [ ${#list_dest} -eq 0 ]; then
        log "No '$target' snapshots on $LUKS_NAME"
    else
        dest_prev=${list_dest[-1]}
        log "Most recent '$target' snapshot on $LUKS_NAME: $dest_prev"
    fi

    # Transfer snapshots
    # TODO: check status of btrfs send | btrfs receive for errors
    for ss in "${list_src[@]}"; do
        if [[ "$ss" < "$OLDEST" ]]; then
            # Handle no previous snapshot case
            if [ -z $dest_prev ]; then
                log "Sending $ss with no base snapshot"
            # Handle snapshot already exists
            # Newest on destination, oldest on source
            # Used to set the base when not starting from a blank slate
            elif [ "$ss" == "$dest_prev" ]; then
                log "$ss already exists on $LUKS_NAME, skipped"
            else
                log "Sending $ss using $dest_prev as the base"

                # Deleting only the base snapshot preserves the most recent
                # moved snapshot to use as a base in the future
                # TODO: delete the base snapshot from the source
                log "Deleting $dest_prev from source"
            fi

            # Update base
            dest_prev=$ss
        fi
    done

    continue

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
