#!/bin/bash

#   Script to build ARM cross-compiler toolchain
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


# Determine host toolchain versions (so cross toolchain matches)
BINVERSION=$(equery -q l sys-devel/binutils | awk -e 'BEGIN{FS="-"} {printf "%s-%s", $3, $4}')
KERNELVERSION=$(equery -q l sys-kernel/gentoo-sources | awk -e 'BEGIN{FS="-"} {print $NF}')
GCCVERSION=$(equery -q l sys-devel/gcc | awk -e 'BEGIN{FS="-"} {printf "%s-%s", $(NF-1), $NF}')
LIBCVERSION=$(equery -q l sys-libs/glibc | awk -e 'BEGIN{FS="-"} {printf "%s-%s", $(NF-1), $NF}')

# Target architecture
TARGET_SHORT="armv6j"
TARGET="$TARGET_SHORT-hardfloat-linux-gnueabi"
REPO="cross-$TARGET"

# Portage repo locations
REPODIR="/var/db/repos/$REPO"
REPOSCONF="/etc/portage/repos.conf"
PORT_LOG="/var/log/portage/$REPO-*.log"
REPO_ROOT="/usr/$TARGET"

# Detect root
if [ $(id -u) -ne 0 ]; then
    echo "Script needs to be run as root."
    exit
fi

# Detect $TARGET toolchain, clean if exists
# Allows for a clean reinstall
if [ -d $REPODIR ]; then
    echo "Cleaning existing $REPO ..."
    crossdev --clean --target $TARGET
    find / -xdev -depth -iname "*${TARGET_SHORT}*" ! -ipath '*repos/gentoo*' -exec rm -r \{\} \;
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

crossdev --init-target --target $TARGET

# Link to /var/tmp/
echo "Linking the repo's temp dir to /var/tmp"
ln -s /var/tmp $REPO_ROOT/tmp

# What we want
CONF_ARCH="arm"
CONF_FEATURES="-collision-protect candy ipc-sandbox network-sandbox noman noinfo nodoc parallel-fetch parallel-install preserve-libs sandbox userfetch userpriv usersandbox usersync"
CONF_CFLAGS="-0fast -mfpu=vfp -mfloat-abi=hard -march=armv6zk -mtune=arm1176jzf-s -fomit-frame-pointer -pipe -fno-stack-protector -U_FORTIFY_SOURCE"
CONF_MAKEOPTS="-j16"

# Modify overlay's make.conf
echo "Setting ARCH=\"$CONF_ARCH\""
sed -ri -e "/^CHOST/i ARCH=\"$CONF_ARCH\"" $REPO_ROOT/etc/portage/make.conf
echo "Setting CFLAGS=\"$CONF_CFLAGS\""
sed -ri -e "/^CFLAGS/c CFLAGS=\"$CONF_CFLAGS\"" $REPO_ROOT/etc/portage/make.conf
echo "Setting FEATURES=\"$CONF_FEATURES\""
sed -ri -e "/^FEATURES/c FEATURES=\"$CONF_FEATURES\"" $REPO_ROOT/etc/portage/make.conf
echo "Setting MAKEOPTS=\"$CONF_MAKEOPTS\""
sed -ri -e "/^FEATURES/i MAKEOPTS=\"$CONF_MAKEOPTS\"" $REPO_ROOT/etc/portage/make.conf

# Create the cross-compiler
echo "Creating toolchain for $TARGET..."
echo "binutils version: $BINVERSION"
echo "Kernel version:   $KERNELVERSION"
echo "GCC version:      $GCCVERSION"
echo "libc version:     $LIBCVERSION"
crossdev    --target $TARGET \
            --stage3 --binutils $BINVERSION --gcc $GCCVERSION --kernel $KERNELVERSION --libc $LIBCVERSION \
            --ex-gdb \
            --denv 'USE="xml"' \
            --portage -a --portage -v
