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

# TODO: flag to determine if run by cron
# TODO: flag for taking snapshots
# TODO: flag for transfering snapshots


# Ensure the return value of a pipeline is 0 only if all commands in it succeed
set -o pipefail

# Pre-declare config file variables
# Declare *_SUBVOLUMES to be an associative array (ie, map)
declare -A TAKE_SUBVOLUMES
declare -A XFER_SUBVOLUMES
# Assigned once a mode is chosen
declare -A SUBVOLUMES

# Import config file
. snapshots.conf

################################################################################
# Common variables
################################################################################
# Reset getopts index
OPTIND=1
# Set by -p
PRETEND=0
# Set by -s
TAKE_MODE=0
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
    echo "NOTE: modes are mutually exclusive"
    echo ""
    echo "Args:"
    echo "    -h    help"
    echo "          Display this help."
    echo "    -l    license"
    echo "          Display license info."
    echo "    -p    pretend"
    echo "          Does everything except for touching snapshots."
    echo "          Doesn't write to syslog."
    echo "    -s    snapshot mode"
    echo "          Take snapshots"
    exit 1
}

# Send message to syslog (except in pretend mode and run by cron)
# arg1: message
log () {
    echo "$*"
    if [ "$PRETEND" -eq 0 ]; then
        echo "$*" >&$LOG_INFO
    fi
}

# Send error to syslog (except in pretend mode and run by cron) and abort
# arg1: error message
die () {
    echo "!!! $*" >&2
    if [ "$PRETEND" -eq 0 ]; then
        echo "!!! $*" >&$LOG_ERR
    fi
    exit 1
}

# Only close/unmount any drives opened/mounted by the script
cleanup () {
    if [ $SRC_MOUNTED -eq 1 ]; then
        if ! (umount "$SRC_SNAPSHOTS"); then
            die "Failed to unmount $SRC_SNAPSHOTS"
        fi

        log "Unmounted $SRC_SNAPSHOTS"
        sleep 0.1
    fi

    if [ $DEST_MOUNTED -eq 1 ]; then
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

# Parse commandline args
while getopts ':hlps' args; do
    case "$args" in
    h)
        usage
        ;;
    l)
        sed -nEe '3,+14 {s/^# *//; p}' $0
        exit 1
        ;;
    p)
        PRETEND=1
        ;;
    s)
        TAKE_MODE=1
        ;;
    *)
        echo "Invalid argument: -$OPTARG"
        usage
        ;;
    esac
done

# Check that a mode was specified
if [ $TAKE_MODE -eq 0 ]; then
    echo "No mode specified"
    usage
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

# Check that the source and destination mountpoints exist
if [ ! -d "$SRC_SNAPSHOTS" ]; then
    die "Mountpoint '$SRC_SNAPSHOTS' not found"
fi
if [ ! -d "$DEST_SNAPSHOTS" ]; then
    die "Mountpoint '$DEST_SNAPSHOTS' not found"
fi

# Check that valid dates were acquired
if [ -z "$DESIRED_PREV" ]; then
    die "Invalid date string '$DESIRED_PREV_CUTOFF'"
fi
if [ -z "$EXPIRED" ]; then
    die "Invalid date string '$EXPIRED_CUTOFF'"
fi

# Mount the snapshot source
if ! (findmnt "$SRC_SNAPSHOTS" &> /dev/null); then
    # Set IFS to create a comma separated list as required by mount(8)
    IFS=','
    if (mount "$SRC_SNAPSHOTS_DEV" "$SRC_SNAPSHOTS" -o "${SRC_MOUNT_OPTS[*]}" &> /dev/null); then
        IFS="$OLD_IFS"
        echo "Mounted $SRC_SNAPSHOTS"
        SRC_MOUNTED=1
    else
        IFS="$OLD_IFS"
        die "Failed to mount $SRC_SNAPSHOTS"
    fi
else
    echo "$SRC_SNAPSHOTS already mounted"
fi

# Mount the snapshot destination
if ! (findmnt "$DEST_SNAPSHOTS" &> /dev/null); then
    # Set IFS to create a comma separated list as required by mount(8)
    IFS=','
    if (mount "$DEST_SNAPSHOTS_DEV" "$DEST_SNAPSHOTS" -o "${DEST_MOUNT_OPTS[*]}" &> /dev/null); then
        IFS="$OLD_IFS"
        echo "Mounted $DEST_SNAPSHOTS"
        DEST_MOUNTED=1
    else
        IFS="$OLD_IFS"
        die "Failed to mount $DEST_SNAPSHOTS"
    fi
else
    echo "$DEST_SNAPSHOTS already mounted"
fi

for target in "${!SUBVOLUMES[@]}"; do
    target_src="$SRC_SNAPSHOTS/${SUBVOLUMES[$target]}"
    target_dest="$DEST_SNAPSHOTS/${SUBVOLUMES[$target]}"

    # Get the list of snapshots
    mapfile -t list_src < <(ls "$target_src")
    mapfile -t list_dest < <(ls "$target_dest")

    # If no snapshots exist, make one
    if [ ${#list_src[@]} -eq 0 ]; then
        echo "No existing snapshots found for $target"
        btrfs subvolume snapshot -r "$target" "$target_src/$NAME"
        sync
        btrfs send "$target_src/$NAME" | btrfs receive "$target_dest"
        sync
        continue
    fi

    src_prev=${list_src[-1]}

    # Check if most recent src snapshot is up to date
    if [[ "$src_prev" < "$DESIRED_PREV" ]]; then
        echo "SRC snapshot '$target_src/$src_prev' is out of date"

        btrfs subvolume snapshot -r "$target" "$target_src/$NAME"
        sync
        list_src=("${list_src[@]}" "$NAME")
        src_prev=$NAME
    fi

    # Check if most recent dest snapshot is up to date
    dest_prev=${list_dest[-1]}

    if [[ "$dest_prev" < "$src_prev" ]]; then
        echo "DEST snapshot '$target_dest/$dest_prev' is out of date"

        # Determine if incremental send is used
        if [ ${#list_src[@]} -ge 2 ]; then
            echo "Previous snapshot of $target is at $target_src/${list_src[-2]}"
            btrfs send -p "$target_src/${list_src[-2]}" "$target_src/${list_src[-1]}" | btrfs receive "$target_dest"
            sync
        else
            echo "No previous snapshot to use as base"
            btrfs send "$target_src/${list_src[-1]}" | btrfs receive "$target_dest"
            sync
        fi
        echo "Sending $target_src/${list_src[-1]} complete"

        # Check for expired src snapshots
        # Only delete if there are > 2 snapshots so that incremental send works
        if [ ${#list_src[@]} -gt 2 ]; then
            if [[ "${list_src[0]}" < "$EXPIRED" ]]; then
                echo "Expired snapshot '$target_src/${list_src[0]}'"
                btrfs subvolume delete "$target_src/${list_src[0]}"
            fi
        else
            echo "Not enough snapshots in '$target_src' to expire"
        fi
    fi
done
