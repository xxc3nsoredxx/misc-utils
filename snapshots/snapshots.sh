#! /bin/bash

#   BTRFS snapshot management script
#   Copyright (C) 2020-2021  xxc3nsoredxx
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

# TODO: manually take a set of snapshots, ignoring date limits


# Ensure the return value of a pipeline is 0 only if all commands in it succeed
set -o pipefail

# Pre-declare config file variables
# Declare *_SUBVOLUMES to be an associative array (ie, map)
declare -A TAKE_SUBVOLUMES
declare -A XFER_SUBVOLUMES

# Import config file
. snapshots.conf

################################################################################
# Common variables
################################################################################
# Reset getopts index
OPTIND=1
# Set by -n
NO_SYSLOG=0
# Set by -p
PRETEND=0
# Set by -s
TAKE_MODE=0
# Set by -t
XFER_MODE=0

# Assigned once a mode is chosen
SRC_SNAPSHOTS_DEV=''
SRC_SNAPSHOTS=''
declare -a SRC_MOUNT_OPTS
DEST_SNAPSHOTS_DEV=''
DEST_SNAPSHOTS=''
declare -a DEST_MOUNT_OPTS
# Declared as a nameref pointing to a map when a mode is chosen
unset SUBVOLUMES

# Set defaults for log file descriptors (stdout, stderr)
LOG_INFO=1
LOG_ERR=2
# Ensure the variable used to hold exit codes is unused/reset
STATUS=0
# Save the IFS value so it can be restored when needed
OLD_IFS="$IFS"

# Flags to control what is cleaned up
SRC_MOUNTED=0
DEST_MOUNTED=0

################################################################################
# Variables related to taking snapshots
################################################################################
# Name of the current snapshot (if one will be taken)
NAME="$(date -I)"
DESIRED_PREV="$(date -I --date="$TAKE_DESIRED_PREV_CUTOFF")"
EXPIRED="$(date -I --date="$TAKE_EXPIRED_CUTOFF")"

################################################################################
# Variables related to transfering snapshots
################################################################################
# Oldest snapshot to keep on source
OLDEST=$(date -I --date="$XFER_OLDEST_CUTOFF")
# udev creates a symlink /dev/ss_crypt pointing to the partition
LUKS_NAME='ss_crypt'
LUKS_DEVICE="/dev/$LUKS_NAME"
# Flags to control what is cleaned up
LUKS_OPENED=0
# cryptsetup(8) exit codes
CRYPT_SUCCESS=0
CRYPT_EXISTS_BUSY=5

# Print usage information
# -h or invalid argument
usage () {
    echo "Usage: $0 [args]"
    echo "NOTE: requires root permissions to run"
    echo "NOTE: modes are mutually exclusive. Uses last one parsed by getopt."
    echo ""
    echo "Args:"
    echo "    -h    help"
    echo "          Display this help."
    echo "    -l    license"
    echo "          Display license info."
    echo "    -n    no syslog"
    echo "          Don't write to syslog. Useful for example when run by cron"
    echo "          and it's already configured to dump output to sylog."
    echo "    -p    pretend"
    echo "          Does everything except for touching snapshots."
    echo "          Implies -n ."
    echo "    -s    snapshot mode"
    echo "          Take snapshots"
    echo "    -t    transfer mode"
    echo "          Transfer snapshots"
    exit 1
}

# Send message to syslog (except in pretend mode and run by cron)
# arg1: message
log () {
    echo "$*"
    if [ $NO_SYSLOG -eq 0 ]; then
        echo "$*" >&$LOG_INFO
    fi
}

# Send error to syslog (except in pretend mode and run by cron) and abort
# arg1: error message
die () {
    echo "!!! $*" >&2
    if [ $NO_SYSLOG -eq 0 ]; then
        echo "!!! $*" >&$LOG_ERR
    fi
    exit 1
}

# Try to mount a drive
# Arg 1: prefix to use in namerefs
# Possible values:
#   'src'
#   'dest'
try_mount () {
    # Create namerefs, convert the prefix to ALL CAPS
    local -n mountpoint="${1^^?}_SNAPSHOTS"
    local -n device="${1^^?}_SNAPSHOTS_DEV"
    # *_MOUNT_OPTS is an array
    local -n mount_opts="${1^^?}_MOUNT_OPTS"
    local -n is_mounted="${1^^?}_MOUNTED"

    # Check that the mountpoint exists
    if [ ! -d "$mountpoint" ]; then
        die "Mountpoint '$mountpoint' not found"
    fi

    # Try to mount
    if ! (findmnt "$mountpoint" &> /dev/null); then
        # Set IFS to create a comma separated list as required by mount(8)
        IFS=','
        if (mount "$device" "$mountpoint" -o "${mount_opts[*]}" &> /dev/null); then
            IFS="$OLD_IFS"
            log "Mounted $mountpoint"
            is_mounted=1
        else
            IFS="$OLD_IFS"
            die "Failed to mount $mountpoint"
        fi
    else
        log "$mountpoint already mounted"
    fi
}

# Try to unmount a drive
# Only unmounts if it was mounted by the script
# Arg 1: prefix to use in namerefs
# Possible values:
#   'src'
#   'dest'
try_unmount () {
    # Create namerefs, convert the prefix to ALL CAPS
    local -n is_mounted="${1^^?}_MOUNTED"
    local -n mountpoint="${1^^?}_SNAPSHOTS"

    if [ $is_mounted -eq 1 ]; then
        if ! (umount "$mountpoint"); then
            die "Failed to unmount $mountpoint"
        fi

        log "Unmounted $mountpoint"
        sleep 0.1
    fi
}

# Try to open a LUKS crypt
# Arg 1: LUKS device name
# Arg 2: path to LUKS keyfile
try_open () {
    # Check that udev's symlink exists
    if [ ! -e "/dev/$1" ]; then
        die "/dev/$1 not found"
    fi

    # Open LUKS crypt
    cryptsetup --key-file "$2" open --type luks "/dev/$1" "$1"
    STATUS=$?
    if [ $STATUS -eq $CRYPT_SUCCESS ]; then
        log "Opened /dev/$1 as $1"
        LUKS_OPENED=1
    elif [ $STATUS -eq $CRYPT_EXISTS_BUSY ]; then
        log "$1 already opened"
    else
        die "Failed to open /dev/$1 as $1"
    fi
}

# Try to close a LUKS crypt
# Arg 1: LUKS device name
try_close () {
    if [ $LUKS_OPENED -eq 1 ]; then
        # Attempt to close LUKS device. If busy, wait a bit and retry a few
        # times. Error if all unsuccessful.
        for i in {1..3}; do
            log "Attempt $i to close $1"
            cryptsetup close "$1"
            STATUS=$?

            if [ $STATUS -eq $CRYPT_EXISTS_BUSY ]; then
                sleep 0.1
            elif [ $STATUS -eq $CRYPT_SUCCESS ]; then
                log "Closed $1"
                break
            else
                die "Failed to close $1"
            fi
        done

        if [ $STATUS -ne $CRYPT_SUCCESS ]; then
            die "Failed to close $1"
        fi
    fi
}

# Only close/unmount any drives opened/mounted by the script
cleanup () {
    try_unmount 'src'
    try_unmount 'dest'
    try_close "$LUKS_NAME"
}

# Try to take a snapshot
# Does nothing in pretend mode
# Arg 1: source subvolume
# Arg 2: target directory
# Arg 3: snapshot name
try_snapshot () {
    log "+++ Creating snapshot '$2/$3'"
    if [ $PRETEND -eq 0 ]; then
        if ! (btrfs subvolume snapshot -r "$1" "$2/$3"); then
            die "Error creating snapshot"
        fi
        sync
    fi
}

# Try to transfer a subvolume
# Does nothing in pretend mode
# Mode 1, transfer subvolume arg1/arg2 into arg3 with no base
#   Arg 1: subvolume source directory
#   Arg 2: subvolume source name
#   Arg 3: subvolume destination directory
# Mode 2, transfer subvolume arg1/arg2 into arg4 with arg1/arg3 as base
#   Arg 1: subvolume source directory
#   Arg 2: subvolume source name
#   Arg 3: base subvolume name
#   Arg 4: subvolume destination directory
try_transfer () {
    # Mode 1, no base
    if [ $# -eq 3 ]; then
        log ">>> Sending $2 with no base snapshot"
        if [ $PRETEND -eq 0 ]; then
            if ! (btrfs send "$1/$2" | btrfs receive "$3"); then
                die "Error sending subvolume '$1/$2'"
            fi
            sync
        fi
    # Mode 2, with base
    elif [ $# -eq 4 ]; then
        log ">>> Sending $2 using $3 as the base"
        if [ $PRETEND -eq 0 ]; then
            if ! (btrfs send -p "$1/$3" "$1/$2" | btrfs receive "$4"); then
                die "Error sending subvolume $1/$2, base $1/$3"
            fi
            sync
        fi
    fi
}

# Try to delete a snapshot
# Arg 1: subvolume source directory
# Arg 2: subvolume source name
try_delete () {
    log "--- Deleting $2 from source"
    if [ $PRETEND -eq 0 ]; then
        if ! (btrfs subvolume delete "$1/$2"); then
            die "Error deleting $1/$2 from source"
        fi
        sync
    fi
}

# Parse commandline args
while getopts ':hlnpst' args; do
    case "$args" in
    h)
        usage
        ;;
    l)
        sed -nEe '3,+14 {s/^# *//; p}' "$0"
        exit 1
        ;;
    n)
        NO_SYSLOG=1
        ;;
    p)
        NO_SYSLOG=1
        PRETEND=1
        ;;
    s)
        TAKE_MODE=1
        XFER_MODE=0
        ;;
    t)
        TAKE_MODE=0
        XFER_MODE=1
        ;;
    *)
        echo "Invalid argument: -$OPTARG"
        usage
        ;;
    esac
done

# Check that a mode was specified
if [ $TAKE_MODE -eq 0 ] && [ $XFER_MODE -eq 0 ]; then
    echo "ERROR: No mode specified"
    usage
fi

# Set up for taking snapshots
if [ $TAKE_MODE -eq 1 ]; then
    SRC_SNAPSHOTS_DEV="$TAKE_SRC_SNAPSHOTS_DEV"
    SRC_SNAPSHOTS="$TAKE_SRC_SNAPSHOTS"
    SRC_MOUNT_OPTS=("${TAKE_SRC_MOUNT_OPTS[@]}")

    DEST_SNAPSHOTS_DEV="$TAKE_DEST_SNAPSHOTS_DEV"
    DEST_SNAPSHOTS="$TAKE_DEST_SNAPSHOTS"
    DEST_MOUNT_OPTS=("${TAKE_DEST_MOUNT_OPTS[@]}")

    declare -n SUBVOLUMES=TAKE_SUBVOLUMES
fi

# Set up for transfering snapshots
if [ $XFER_MODE -eq 1 ]; then
    SRC_SNAPSHOTS_DEV="$XFER_SRC_SNAPSHOTS_DEV"
    SRC_SNAPSHOTS="$XFER_SRC_SNAPSHOTS"
    SRC_MOUNT_OPTS=("${XFER_SRC_MOUNT_OPTS[@]}")

    DEST_SNAPSHOTS_DEV="/dev/mapper/$LUKS_NAME"
    DEST_SNAPSHOTS="$XFER_DEST_SNAPSHOTS"
    DEST_MOUNT_OPTS=("${XFER_DEST_MOUNT_OPTS[@]}")

    declare -n SUBVOLUMES=XFER_SUBVOLUMES
fi

# Create file descriptors for syslog info and syslog err
exec {LOG_INFO}> >(logger --id=$$ --priority daemon.info --tag snapshots_manager)
exec {LOG_ERR}> >(logger --id=$$ --priority daemon.err --tag snapshots_manager)

# Install exit handler
trap cleanup EXIT

# Only run as root
if [ "$(id -u)" -ne 0 ]; then
    die "Snapshots can only be managed by root ($(id -un), id=$(id -u))"
fi

# Try to mount the snapshot source and destination
try_mount 'src'
if [ $XFER_MODE -eq 1 ]; then
    try_open "$LUKS_NAME" "$XFER_LUKS_KEYFILE"
fi
try_mount 'dest'

# Check that valid dates were acquired
if [ $TAKE_MODE -eq 1 ]; then
    if [ -z "$DESIRED_PREV" ]; then
        die "Invalid date string '$DESIRED_PREV_CUTOFF'"
    fi
    if [ -z "$EXPIRED" ]; then
        die "Invalid date string '$EXPIRED_CUTOFF'"
    fi

    log "Desired previous: $DESIRED_PREV"
    log "Expired: $EXPIRED"
fi
if [ $XFER_MODE -eq 1 ]; then
    if [ -z "$OLDEST" ]; then
        die "Invalid date string '$XFER_OLDEST_CUTOFF'"
    fi

    log "Oldest: $OLDEST"
fi

# Loop through the keys of the SUBVOLUMES map
for target in "${!SUBVOLUMES[@]}"; do
    log "$target:"

    target_src="$SRC_SNAPSHOTS/${SUBVOLUMES[$target]}"
    target_dest="$DEST_SNAPSHOTS/${SUBVOLUMES[$target]}"

    # Get the list of snapshots
    mapfile -t list_src < <(ls "$target_src")
    mapfile -t list_dest < <(ls "$target_dest")

    # Snapshot mode
    if [ $TAKE_MODE -eq 1 ]; then
        # If no snapshots exist, make one
        if [ ${#list_src[@]} -eq 0 ]; then
            log "No existing snapshots found on $SRC_SNAPSHOTS"

            try_snapshot "$target" "$target_src" "$NAME"
            try_transfer "$target_src" "$NAME" "$target_dest"

            continue
        fi

        # Check if most recent src snapshot is up to date
        src_prev="${list_src[-1]}"
        log "Latest src: $src_prev"
        if [[ "$src_prev" < "$DESIRED_PREV" ]]; then
            try_snapshot "$target" "$target_src" "$NAME"

            # Add to the end of src snapshots list and set as previous snapshot
            list_src=("${list_src[@]}" "$NAME")
            src_prev=$NAME
        fi

        # Check if most recent dest snapshot is up to date
        dest_prev="${list_dest[-1]}"
        log "Latest dest: $dest_prev"
        if [[ "$dest_prev" < "$src_prev" ]]; then
            # Determine if incremental send is used
            if [ ${#list_src[@]} -ge 2 ]; then
                try_transfer "$target_src" "$src_prev" "${list_src[-2]}" "$target_dest"
            else
                try_transfer "$target_src" "$src_prev" "$target_dest"
            fi
        fi

        # Check for expired src snapshots
        # Only delete if there are > 2 snapshots so that incremental send works
        if [ ${#list_src[@]} -gt 2 ]; then
            for del in "${list_src[@]}"; do
                if [[ "$del" < "$EXPIRED" ]]; then
                    log "Expired snapshot '$target_src/$del'"
                    try_delete "$target_src" "$del"
                fi
            done
        else
            log "Not enough snapshots in '$target_src' to expire"
        fi
    # Transfer mode
    elif [ $XFER_MODE -eq 1 ]; then
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
                    try_transfer "$target_src" "$ss" "$target_dest"
                # Normal case
                # Newest on destination is used as the base, sends second oldest on source
                else
                    try_transfer "$target_src" "$ss" "$base" "$target_dest"

                    # Deleting only the base snapshot preserves the most recent
                    # moved snapshot to use as a base in the future
                    try_delete "$target_src" "$base"
                fi

                # Update base
                base=$ss
            fi
        done
    fi
done

log "Done!"
