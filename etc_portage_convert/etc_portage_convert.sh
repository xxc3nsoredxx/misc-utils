#! /bin/bash

#   Naive conversion of /etc/portage from flat files to directories
#   Copyright (C) 2022  Oskari Pirhonen <xxc3ncoredxx@gmail.com>
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

DEBUG=${DEBUG@L}
GENTOO_FUNCTIONS="/lib/gentoo/functions.sh"
USE_GENTOO=0
# Don't log to syslog with the Gentoo functions
EINFO_LOG=""

# Print message to stderr
err () {
    echo "$@" >&2
}

# Print message to stderr only if debug is enabled
debug () {
    if [ "${DEBUG:0:1}" == y ] || [ "${DEBUG:0:1}" == 1 ]; then
        if [ $# -gt 0 ]; then
            err "DDD $@"
        fi
    fi
}

# Print error to stderr
error () {
    if [ $USE_GENTOO -eq 1 ]; then
        [ $# -gt 0 ] && eerror "$@"
    else
        [ $# -gt 0 ] && err "!!! $@"
    fi
}

# Print message to stderr (if given) and exit with failure
die () {
    error "$@"
    exit 1
}

# Print an informative message
info () {
    if [ $USE_GENTOO -eq 1 ]; then
        [ $# -gt 0 ] && einfo "$@"
    else
        echo "$@"
    fi
}


debug "debug on"

# Basic sanity checks
if [ ! -f "$GENTOO_FUNCTIONS" ]; then
    error "$GENTOO_FUNCTIONS not found, using boring messages ;("
else
    source "$GENTOO_FUNCTIONS"
    USE_GENTOO=1
fi
[ $(id -u) -eq 0 ]  || die "$0 must be run as root"
PORTAGEQ="$(command -v portageq)"
[ -n "$PORTAGEQ" ]  || die "portageq not found"
CONF_DIR="$("$PORTAGEQ" envvar PORTAGE_CONFIGROOT)/etc/portage"
[ -d "$CONF_DIR" ]  || die "$CONF_DIR not found or not a directory"
BU_DIR="$(mktemp -d /tmp/etc_portage.XXXXXX)"
[ -d "$BU_DIR" ]    || die "unable to create backup dir $BU_DIR"

cp -a "$CONF_DIR"/* "$BU_DIR"
if [ $? -ne 0 ]; then
    rm -rf "$BU_DIR"
    die "unable to backup $CONF_DIR to $BU_DIR"
fi
info "backup: $BU_DIR"

# Check for flat files that can be turned into directories
for file in "$CONF_DIR/repos.conf" \
            "$CONF_DIR"/package.*
do
    # Literal "package.*" most likely means no package.* files/dirs. Safe to
    # skip either way.
    [ "$file" != "$CONF_DIR/package.*" ] || continue

    # If it's already a directory, safe to skip
    if [ -d "$file" ]; then
        info "skip $file: already a directory"
        continue
    fi

    new_file="$(basename "$file").orig"
    temp="$(mktemp "$file.XXXXXX")"
    debug "using temp file $temp"

    [ $USE_GENTOO -eq 1 ] && ebegin "convert: $file -> $file/$new_file"

    mv "$file" "$temp"
    if [ $? -ne 0 ]; then
        if [ $USE_GENTOO -eq 1 ]; then
            ewend 1 "unable to back up to temp file, skipping..."
        else
            error "unable to back up $file to temp file, skipping..."
        fi
        rm -f "$temp"
        continue
    fi

    mkdir "$file"
    if [ $? -ne 0 ]; then
        if [ $USE_GENTOO -eq 1 ]; then
            ewend 1 "unable to create directory, restoring and skipping..."
        else
            error "unable to create directory for $file, restoring and skipping..."
        fi
        mv "$temp" "$file"
        continue
    fi

    mv "$temp" "$file/$new_file"
    if [ $? -ne 0 ]; then
        if [ $USE_GENTOO -eq 1 ]; then
            ewend 1 "unable to move backup to directory, restoring and skipping..."
        else
            error "unable to move backup to directory $file, restoring and skipping..."
        fi
        rm -rf "$file"
        mv "$temp" "$file"
        continue
    fi

    if [ $USE_GENTOO -eq 1 ]; then
        eend
    else
        info "convert: $file -> $file/$new_file"
    fi
done
