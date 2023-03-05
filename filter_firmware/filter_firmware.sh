#! /bin/bash

#   Script to filter sys-kernel/linux-firmware `savedconfig` file
#   Copyright (C) 2020-2022  xxc3nsoredxx
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


# Must be run as root
if [ $(id -u) -ne 0 ]; then
    echo "$0 must be run as root"
    exit -1
fi

# The most recent one should be the one just installed
SAVEDCONFIG="/etc/portage/savedconfig/sys-kernel"
SAVES=($(ls $SAVEDCONFIG/linux-firmware* | xargs basename -a))
TARGET=${SAVES[-1]}
# Directory to save backups to
BU_DIR="$HOME/config_backups"
# Temp file to aggregate list of firmwares into
TEMP="$(mktemp --tmpdir firmware_XXX)"

# Ensure backup directory exists
mkdir -p "$BU_DIR"

echo "Making a backup of the full list into '$BU_DIR/$TARGET.bu'"
cp "$SAVEDCONFIG/$TARGET" "$BU_DIR/$TARGET.bu"

# Create a clean slate
for CONFIG in "${SAVES[@]}"; do
    rm "$SAVEDCONFIG/$CONFIG"
done

echo "Collecting firmware into '$TEMP'"

# Collect firmware from loaded modules
lsmod | tail +2 | cut -d ' ' -f 1 | xargs modinfo | grep -i 'firmware:' | tr -s ' ' | cut -d ' ' -f 2 > "$TEMP"

# Collect firmware from dmesg(1)
# Requires CONFIG_GENTOO_PRINT_FIRMWARE_INFO
dmesg -r | grep 'Loading firmware:' | tr -s ' ' | cut -d ' ' -f 5 >> "$TEMP"

sort "$TEMP" | uniq > "${TEMP}_filtered"

# Filter by currently used firmware
for FW in $(< "${TEMP}_filtered"); do
    echo -n "$FW: "
    if (grep -q "$FW" "$BU_DIR/$TARGET.bu"); then
        echo "$FW" >> "$SAVEDCONFIG/$TARGET"
        echo 'added'
    else
        echo 'NOT found, NOT added'
    fi
done

echo "Removing temp files"
rm "$TEMP" "${TEMP}_filtered"

# Re-emerge to only include the needed firmware
emerge -1 sys-kernel/linux-firmware
