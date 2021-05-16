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

# TODO: flag for taking snapshots
# TODO: pretend mode for taking snapshots
# TODO: flag for transfering snapshots
# TODO: loop deleting all expired snapshots


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
LUKS_DEVICE='/dev/ss_crypt'
LUKS_NAME='ss_crypt'
# Flags to control what is cleaned up
LUKS_OPENED=0
LUKS_MOUNTED=0
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

# Only close/unmount any drives opened/mounted by the script
cleanup () {
    try_unmount 'src'
    try_unmount 'dest'

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

# Try to take a snapshot
# Does nothing in pretend mode
# Arg 1: source subvolume
# Arg 2: target directory
# Arg 3: snapshot name
try_snapshot () {
    log "Creating snapshot '$2/$3'"
    if [ $PRETEND_MODE -eq 0 ]; then
        if ! (btrfs subvolume snapshot -r "$1" "$2/$3"); then
            die "Error creating snapshot"
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
        sed -nEe '3,+14 {s/^# *//; p}' $0
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
    echo 'Transfer mode not implemented yet!'
    exit 1
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

# Check that valid dates were acquired
if [ $TAKE_MODE -eq 1 ]; then
    if [ -z "$DESIRED_PREV" ]; then
        die "Invalid date string '$DESIRED_PREV_CUTOFF'"
    fi
    if [ -z "$EXPIRED" ]; then
        die "Invalid date string '$EXPIRED_CUTOFF'"
    fi
fi

# Try to mount the snapshot source and destination
try_mount 'src'
try_mount 'dest'

exit

# Loop through the keys of the SUBVOLUMES map
for target in "${!SUBVOLUMES[@]}"; do
    log "$target:"

    target_src="$SRC_SNAPSHOTS/${SUBVOLUMES[$target]}"
    target_dest="$DEST_SNAPSHOTS/${SUBVOLUMES[$target]}"

    # Get the list of snapshots
    mapfile -t list_src < <(ls "$target_src")
    mapfile -t list_dest < <(ls "$target_dest")

    # If no snapshots exist, make one
    if [ ${#list_src[@]} -eq 0 ]; then
        log "No existing snapshots found on $SRC_SNAPSHOTS"

        try_snapshot "$target" "$target_src" "$NAME"

        log ">>> Sending $NAME with no base snapshot"
        if ! (btrfs send "$target_src/$NAME" | btrfs receive "$target_dest"); then
            die "Error sending subvolume '$target_src/$NAME'"
        fi
        sync
        continue
    fi

    src_prev="${list_src[-1]}"

    # Check if most recent src snapshot is up to date
    if [[ "$src_prev" < "$DESIRED_PREV" ]]; then
        log "SRC snapshot '$target_src/$src_prev' is out of date"

        try_snapshot "$target" "$target_src" "$NAME"

        # Add to the end of src snapshots list and set as previous snapshot
        list_src=("${list_src[@]}" "$NAME")
        src_prev=$NAME
    fi

    # Check if most recent dest snapshot is up to date
    dest_prev="${list_dest[-1]}"

    if [[ "$dest_prev" < "$src_prev" ]]; then
        log "DEST snapshot '$target_dest/$dest_prev' is out of date"

        # Determine if incremental send is used
        if [ ${#list_src[@]} -ge 2 ]; then
            log ">>> Sending $target_src/$src_prev using ${list_src[-2]} as the base"
            if ! (btrfs send -p "$target_src/${list_src[-2]}" "$target_src/$src_prev" | btrfs receive "$target_dest"); then
                die "Error sending subvolume $target_src/$src_prev, base $target_src/${list_src[-2]}"
            fi
            sync
        else
            log ">>> Sending $target_src/$src_prev with no base snapshot"
            if ! (btrfs send "$target_src/$src_prev" | btrfs receive "$target_dest"); then
                die "Error sending subvolume $target_src/$src_prev"
            fi
            sync
        fi

        # Check for expired src snapshots
        # Only delete if there are > 2 snapshots so that incremental send works
        if [ ${#list_src[@]} -gt 2 ]; then
            if [[ "${list_src[0]}" < "$EXPIRED" ]]; then
                log "Expired snapshot '$target_src/${list_src[0]}'"
                if ! (btrfs subvolume delete "$target_src/${list_src[0]}"); then
                    die "Error deleting $target_src/${list_src[0]} from source"
                fi
            fi
        else
            log "Not enough snapshots in '$target_src' to expire"
        fi
    fi
done

log "Done!"
