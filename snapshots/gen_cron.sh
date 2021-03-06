#! /bin/bash
# snapshots/gen_cron.sh.  Generated from gen_cron.sh.in by configure.

#   Script to generate snapshot cron job
#   Copyright (C) 2021  xxc3nsoredxx
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

# Arg 1: name of cron job file

# Pre-declare config file variables
# Declare *_SUBVOLUMES to be an associative array (ie, map)
declare -A TAKE_SUBVOLUMES
declare -A XFER_SUBVOLUMES
# Get config options
. snapshots.conf
CRON_SHELL='/bin/bash'
CRON_PATH='/sbin:/bin:/usr/sbin:/usr/bin'
CRON_MAILTO='root'
transform='s,x,x,'
# Fix any double-$ from autoconf
transform="${transform/'$$'/$}"

cat > "$1" << EOF
SHELL=$CRON_SHELL
PATH=$CRON_PATH
MAILTO=$CRON_MAILTO
${CRON_MINUTES:-*} ${CRON_HOURS:-*} ${CRON_DAYS_MONTH:-*} ${CRON_MONTHS:-*} ${CRON_DAYS_WEEK:-*} root $(echo 'snapshots.sh' | sed -e $transform) -ns
EOF
