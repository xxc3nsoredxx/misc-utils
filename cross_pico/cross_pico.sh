#! /bin/bash

#   Script to build Arm cross-compiler toolchain targetting RPi Pico
#   Copyright (C) 2021-2022  Oskari Pirhonen <xxc3ncoredxx@gmail.com>
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

# Target architecture
TARGET_SHORT="arm"
TARGET="$TARGET_SHORT-none-eabi"
REPO="cross-$TARGET"

# Portage repo locations
REPODIR="/var/db/repos/$REPO"
REPOSCONF="/etc/portage/repos.conf"
PORT_LOG="/var/log/portage/$REPO-*.log"
REPO_ROOT="/usr/$TARGET"

# Detect root
if [ $(id -u) -ne 0 ]; then
    echo "'$0' needs to be run as root."
    exit 1
fi

# Detect $TARGET toolchain, clean if exists
# Allows for a clean reinstall
if [ -d $REPODIR ]; then
    echo "Cleaning existing $REPO ..."
    crossdev --clean --target $TARGET
    find / -xdev -ipath "*${TARGET}*" ! -ipath '*repos/gentoo*' -delete
fi

# Create overlay
echo "Creating repo $REPO ..."
mkdir -p $REPODIR/{profiles,metadata}
echo "$REPO" > $REPODIR/profiles/repo_name
echo 'masters = gentoo' > $REPODIR/metadata/layout.conf
echo "[$REPO]" > $REPOSCONF/$REPO.conf
echo "location = $REPODIR" >> $REPOSCONF/$REPO.conf
echo 'priority = 10' >> $REPOSCONF/$REPO.conf
echo 'masters = gentoo' >> $REPOSCONF/$REPO.conf
echo 'auto-sync = no' >> $REPOSCONF/$REPO.conf
chown -R portage:portage $REPODIR

crossdev    --target $TARGET    \
            --init-target

# Link to /var/tmp/
echo "Linking the repo's temp dir to /var/tmp"
ln -s /var/tmp $REPO_ROOT/tmp

# What we want
CONF_CFLAGS="-O2 -pipe -fomit-frame-pointer -march=armv6-m -mtune=cortex-m0plus -mthumb"
CONF_MAKEOPTS="-j$(nproc)"
CONF_FEATURES="-collision-protect candy ipc-sandbox network-sandbox noman noinfo nodoc parallel-fetch parallel-install preserve-libs sandbox userfetch userpriv usersandbox usersync"

# Modify overlay's make.conf
echo "Setting CFLAGS=\"$CONF_CFLAGS\""
sed -i -e "/^CFLAGS/c CFLAGS=\"$CONF_CFLAGS\"" $REPO_ROOT/etc/portage/make.conf
echo "Setting FEATURES=\"$CONF_FEATURES\""
sed -i -e "/^FEATURES/c FEATURES=\"$CONF_FEATURES\"" $REPO_ROOT/etc/portage/make.conf
echo "Setting MAKEOPTS=\"$CONF_MAKEOPTS\""
sed -i -e "/^CXXFLAGS/a MAKEOPTS=\"$CONF_MAKEOPTS\"" $REPO_ROOT/etc/portage/make.conf

echo "Fixing kernel settings"
sed -i -e "s/ __KERNEL__//" $REPO_ROOT/etc/portage/profile/make.defaults
sed -i -e "/KERNEL/d" $REPO_ROOT/etc/portage/profile/use.force

# Create the cross-compiler
echo "Creating toolchain for $TARGET..."
crossdev    --target $TARGET    \
            --stage4            \
            --portage -a --portage -v
