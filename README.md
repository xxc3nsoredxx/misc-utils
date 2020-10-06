# misc-utils

A collection of miscellaneous little utils that I don't feel deserve a full repo.

## snapshots

A bash script for taking snapshots of a BTRFS filesystem.
Uses the number of existing snapshots of a given subvolume to determine if incremental send is used.
Assumes that the destination has *at least* the same snapshots as the source.
Designed to be run at regular intervals in a cron job.
The default snapshot name is of the form `YYYY-MM-DD` which means it doesn't make sense to run more than once every 24 hours.

 * `SRC_SNAPSHOTS` is the path to the main snapshot subvolume
 * `DEST_SNAPSHOTS` is the path to the backup snapshot subvolume (prefarably on a separate storage medium)
 * `SUBVOLUMES` is an associative array of `[path] -> [subvolume name]` to describe what needs to be snapshotted
 * `NAME` is the name given to each snapshot
    * Must be unique each time the script is run
    * Must be sortable in chronological order by name

## only_required_firmware

A bash script to filter the config file for the Gentoo package `sys-kernel/linux-firmware`.
Parses the output of `modinfo` for each module given by `lsmod` for required firmware files.
Re-emerges the package at the end.

### Requirements

 * Must be run as root
 * `savedconfig` USE flag for `sys-kernel/linux-firmware` is set

## userscripts

A collection of scripts loaded into [Greasemonkey](https://www.greasespot.net).
Eventually.
Currently there is just the one.

### mobile_to_desktop

Redirects a mobile page to a desktop page.
Inspired by all the people on Reddit posting links to https://en.m.wikipedia.org which, for some reason, doesn't go to the desktop page on desktop browsers.
The other way around works just fine -- desktop Wikipedia on a mobile browser redirects to mobile Wikipedia.
Currently only has Wikipedia listed in the URLs to convert.
More will be added if/as needed.

You can use the Wikipedia link above to conveniently test the script after installation.
A completely unintentional side effect of the link automatically being generated for the text.

[Click here to install the userscript](https://github.com/xxc3nsoredxx/misc-utils/raw/master/userscripts/mobile_to_desktop.user.js)
