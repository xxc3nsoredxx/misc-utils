#! /bin/bash

# Ensure the return value of a pipeline is 0 only if all commands in it succeed
set -o pipefail

# Pre-declare config file variables
# Declare SUBVOLUMES to be an associative array (ie, map)
declare -A SUBVOLUMES

# Import config file
. transfer.conf

# Reset getopts index
OPTIND=1

# Flag to control sending/deleting
# Set by -p
PRETEND=0

# Set defaults for log file descriptors (stdout, stderr)
LOG_INFO=1
LOG_ERR=2

# Oldest snapshot to keep on source
OLDEST=$(date -I --date="$OLDEST_CUTOFF")

# Ensure the variable used to hold exit codes is unused/reset
STATUS=0

# Save the IFS value so it can be restored when needed
OLD_IFS="$IFS"

# udev creates a symlink /dev/ss_crypt pointing to the partition
LUKS_DEVICE='/dev/ss_crypt'
LUKS_NAME='ss_crypt'

# Flags to control what is cleaned up
LUKS_OPENED=0
LUKS_MOUNTED=0
SRC_MOUNTED=0
# cryptsetup(8) exit codes
CRYPT_SUCCESS=0
CRYPT_EXISTS_BUSY=5

# Print usage information
# -h or invalid argument
usage () {
    echo "Usage: $0 [args]"
    echo "NOTE: requires root permissions to run"
    echo ""
    echo "Args:"
    echo "    -h    help"
    echo "          Display this help."
    echo "    -p    pretend"
    echo "          Does everything except for transferring/deleting snapshots."
    echo "          Doesn't write to syslog."
    exit 1
}

# Close LUKS and unmount if needed
# Only close/unmount the ones opened/mounted by the script
cleanup () {
    if [ $SRC_MOUNTED -eq 1 ]; then
        if ! (umount "$SRC_SNAPSHOTS"); then
            die "Failed to unmount $SRC_SNAPSHOTS"
        fi

        log "Unmounted $SRC_SNAPSHOTS"
        sleep 0.1
    fi

    if [ $LUKS_MOUNTED -eq 1 ]; then
        if ! (umount "$DEST_SNAPSHOTS"); then
            die "Failed to unmount $DEST_SNAPSHOTS"
        fi

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

# Send message to syslog (except in pretend mode)
# arg1: message
log () {
    echo "$*"
    if [ "$PRETEND" -eq 0 ]; then
        echo "$*" >&$LOG_INFO
    fi
}

# Send error to syslog (except in pretend mode) and abort
# arg1: error message
die () {
    echo "!!! $*" >&2
    if [ "$PRETEND" -eq 0 ]; then
        echo "!!! $*" >&$LOG_ERR
    fi
    exit 1
}

# Parse commandline args
while getopts ':hp' args; do
    case "$args" in
    h)
        usage
        ;;
    p)
        PRETEND=1
        ;;
    *)
        echo "Invalid argument: -$OPTARG"
        usage
        ;;
    esac
done

# Create file descriptors for syslog info and syslog err
exec {LOG_INFO}> >(logger --id=$$ --priority daemon.info --tag ss_crypt_transfer)
exec {LOG_ERR}> >(logger --id=$$ --priority daemon.err --tag ss_crypt_transfer)

# Install exit handler
trap cleanup EXIT

# Only run as root
if [ "$(id -u)" -ne 0 ]; then
    die "Snapshots can only be transferred as root ($(id -un), id=$(id -u))"
fi

# Check that the source and destination mountpoints exist
if [ ! -d "$SRC_SNAPSHOTS" ]; then
    die "Mountpoint '$SRC_SNAPSHOTS' not found"
fi
if [ ! -d "$DEST_SNAPSHOTS" ]; then
    die "Mountpoint '$DEST_SNAPSHOTS' not found"
fi

# Check that LUKS key-file exists
if [ ! -f "$LUKS_KEYFILE" ]; then
    die "Key-file '$LUKS_KEYFILE' not found"
fi

# Check that a valid date was acquired
if [ -z "$OLDEST" ]; then
    die "Invalid date string '$OLDEST_CUTOFF'"
fi

# Check that udev's symlink exists
if [ ! -e $LUKS_DEVICE ]; then
    die "$LUKS_DEVICE not found"
fi

# Open LUKS crypt
cryptsetup --key-file "$LUKS_KEYFILE" open --type luks $LUKS_DEVICE $LUKS_NAME
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
if ! (findmnt "$DEST_SNAPSHOTS" &> /dev/null); then
    # Set IFS to create a comma separated list as required by mount(8)
    IFS=','
    if (mount "/dev/mapper/$LUKS_NAME" "$DEST_SNAPSHOTS" -o "${DEST_MOUNT_OPTS[*]}" &> /dev/null); then
        IFS="$OLD_IFS"
        log "Mounted $LUKS_NAME onto $DEST_SNAPSHOTS"
        LUKS_MOUNTED=1
    else
        IFS="$OLD_IFS"
        die "Failed to mount $LUKS_NAME onto $DEST_SNAPSHOTS"
    fi
else
    log "$DEST_SNAPSHOTS already mounted"
fi

# Mount the snapshot source
if ! (findmnt "$SRC_SNAPSHOTS" &> /dev/null); then
    # Set IFS to create a comma separated list as required by mount(8)
    IFS=','
    if (mount "$SRC_SNAPSHOTS_DEV" "$SRC_SNAPSHOTS" -o "${SRC_MOUNT_OPTS[*]}" &> /dev/null); then
        IFS="$OLD_IFS"
        log "Mounted $SRC_SNAPSHOTS"
        SRC_MOUNTED=1
    else
        IFS="$OLD_IFS"
        die "Failed to mount $SRC_SNAPSHOTS"
    fi
else
    log "$SRC_SNAPSHOTS already mounted"
fi

log "Transfer cutoff: $OLDEST"
# Loop through the keys of the $SUBVOLUMES map
for target in "${!SUBVOLUMES[@]}"; do
    log "$target:"

    target_src=$SRC_SNAPSHOTS/${SUBVOLUMES[$target]}
    target_dest=$DEST_SNAPSHOTS/${SUBVOLUMES[$target]}

    # Get the list of snapshots
    mapfile -t list_src < <(ls "$target_src")
    mapfile -t list_dest < <(ls "$target_dest")

    # Get the most recent snapshot on the destination drive to use as a base
    base=''
    if [ ${#list_dest} -eq 0 ]; then
        log "No '$target' snapshots on $LUKS_NAME"
    else
        base=${list_dest[-1]}
        log "Most recent '$target' snapshot on $LUKS_NAME: $base"
    fi

    # Transfer snapshots
    for ss in "${list_src[@]}"; do
        if [[ "$ss" < "$OLDEST" ]]; then
            # Handle newest on destination == oldest on source
            # Used to set the base when not starting from a blank slate
            if [ "$ss" == "$base" ]; then
                log "$ss already exists on $LUKS_NAME, skipped"
            # Handle no previous snapshot case
            # Used when first sending snapshots to a new drive
            elif [ -z "$base" ]; then
                log ">>> Sending $ss with no base snapshot"
                if [ "$PRETEND" -eq 0 ]; then
                    if ! (btrfs send "$target_src/$ss" | btrfs receive "$target_dest"); then
                        die "Error sending subvolume '$target_src/$ss'"
                    fi

                    sync
                fi
            # Normal case
            # Newest on destination is used as the base, sends second oldest on source
            else
                log ">>> Sending $ss using $base as the base"
                if [ "$PRETEND" -eq 0 ]; then
                    if ! (btrfs send -p "$target_src/$base" "$target_src/$ss" | btrfs receive "$target_dest"); then
                        die "Error sending subvolume '$target_src/$ss', base '$target_src/$base'"
                    fi
                fi

                # Deleting only the base snapshot preserves the most recent
                # moved snapshot to use as a base in the future
                log "--- Deleting $base from source"
                if [ "$PRETEND" -eq 0 ]; then
                    if ! (btrfs subvolume delete "$target_src/$base"); then
                        die "Error deleting $base from source"
                    fi

                    sync
                fi
            fi

            # Update base
            base=$ss
        fi
    done
done
