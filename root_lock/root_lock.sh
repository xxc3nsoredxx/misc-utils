#! /bin/bash

#   Lock the system if root is logged in
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


LOCK_CMD='physlock'
LOCK_ARGS='-s'

# Get controlling TTYs of physical logins
ROOT_PHYS=($(w -h root | tr -s ' ' | cut -d ' ' -f 2))
ROOT_PHYS=(${ROOT_PHYS[@]//[^0-9]})

# Get controlling TTYs of su(1) logins
ROOT_SU=($(ps -C su --no-headers -o tty))
ROOT_SU=(${ROOT_SU[@]//[^0-9]})

# Check we're running as root
if [ $(id -u) -ne 0 ]; then
    exit 0
fi

# Don't stack locks
if ! (ps -C $LOCK_CMD &>/dev/null); then
    if [ ${#ROOT_PHYS[@]} -gt 0 ]; then
        # Switch to root owned TTY
        chvt $ROOT_PHYS
        (openvt -s -w -- $LOCK_CMD $LOCK_ARGS)&
        exit 1
    elif [ ${#ROOT_SU[@]} -gt 0 ]; then
        # Switch to su(1)'s controlling TTY
        chvt $ROOT_SU
        (openvt -s -w -- $LOCK_CMD $LOCK_ARGS)&
        exit 1
    fi
fi

exit 0
