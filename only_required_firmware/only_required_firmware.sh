#! /bin/bash

#   Script to filter sys-kernel/linux-firmware `savedconfig` file
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
BU_DIR=$HOME/config_backups

# Ensure backup directory exists
mkdir -p $BU_DIR

echo "Making a backup of the full list into $BU_DIR/$TARGET.bu"
cp $SAVEDCONFIG/$TARGET $BU_DIR/$TARGET.bu

# Create a clean slate
for CONFIG in ${SAVES[@]}; do
    rm $SAVEDCONFIG/$CONFIG
done

# Filter by currently used firmware
for FW in $(lsmod | tail +2 | cut -d ' ' -f 1 | xargs modinfo | grep -i 'firmware:' | tr -s ' ' | cut -d ' ' -f 2); do
    echo -n "$FW: "
    if [ "$(grep -q $FW $BU_DIR/$TARGET.bu)" == '0' ]; then
        echo 'NOT found, NOT added'
    else
        echo "$FW" >> $SAVEDCONFIG/$TARGET
        echo 'added'
    fi
done

# Re-emerge to only include the needed firmware
emerge sys-kernel/linux-firmware
