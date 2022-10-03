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

# Print message to stderr
err () {
    echo "$@" >&2
}

# Print message to stderr only if debug is enabled
debug () {
    if [ $# -gt 0 ]; then
        if [ "${DEBUG:0:1}" == y ] || [ "${DEBUG:0:1}" == 1 ]; then
            err "DDD $@"
        fi
    fi
}

# Print error to stderr
error () {
    [ $# -gt 0 ] && err "!!! $@"
}

# Print message to stderr (if given) and exit with failure
die () {
    error "$@"
    exit 1
}

debug "debug on"

# Basic sanity checks
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
echo "backup: $BU_DIR"

# Check for flat files that can be turned into directories
# TODO:
#   - include make.conf in this or no? idk if jannik was being silly or serious
#     (my guess is silly)
for file in "$CONF_DIR/repos.conf" \
            "$CONF_DIR"/package.*
do
    # Literal "package.*" most likely means no package.* files/dirs. Safe to
    # skip either way.
    [ "$file" != "$CONF_DIR/package.*" ] || continue

    # If it's already a directory, safe to skip
    if [ -d "$file" ]; then
        echo "skip $file: already a directory"
        continue
    fi

    new_file="$(basename "$file").orig"
    temp="$(mktemp "$file.XXXXXX")"
    debug "using temp file $temp"

    mv "$file" "$temp"
    if [ $? -ne 0 ]; then
        error "unable to back up $file to temp file, skipping..."
        rm -f "$temp"
        continue
    fi

    mkdir "$file"
    if [ $? -ne 0 ]; then
        error "unable to create directory for $file, restoring and skipping..."
        mv "$temp" "$file"
        continue
    fi

    mv "$temp" "$file/$new_file"
    if [ $? -ne 0 ]; then
        error "unable to move backup to directory $file, restoring and skipping..."
        rm -rf "$file"
        mv "$temp" "$file"
        continue
    fi

    echo "convert: $file -> $file/$new_file"
done
