# misc-utils

A collection of miscellaneous little utils that I don't feel deserve a full repo.

## genhash
Creates an `/etc/shadow`-friendly SHA-512 hash given a password and a salt.
`crypt(3)` allows for up to 16 characters in the salt from the character set `[a-zA-Z0-9./]`.
A salt argument longer than 16 characters gets truncated down, and invalid characters get converted into '.'.
To compile, just run `make` in the `genhash/` directory.

```
Usage: genhash [password] [salt]
```

## only_required_firmware
A bash script to filter the config file for the Gentoo package `sys-kernel/linux-firmware`.
Parses the output of `modinfo` for each module given by `lsmod` for required firmware files.
I recommend rebooting after updating the package so that any new firmware files get loaded and are found by the script.
Re-emerges the package at the end (which will clean up any installed but unused firmware files from the system).

### Requirements
 * Must be run as root
 * `savedconfig` USE flag for `sys-kernel/linux-firmware` is set

## root_lock
If root is logged in, locks the machine requiring the root password to unlock.
Works for physical logins as well as `su(1)`.
Companion script for [locking the machine when my Yubikey is removed][yubikey].

### Requirements
 * Must be run as root
   * Designed to be run as part of a system service

## snapshots
A bash script for taking snapshots of a BTRFS filesystem.
Uses the number of existing snapshots of a given subvolume to determine if incremental send is used.
Assumes that the destination has *at least* the same snapshots as the source.
The default snapshot name is of the form `YYYY-MM-DD`.
Designed to be run at regular intervals in a cron job.
The script can be run repeatedly to verify that snapshots have been taken.
This means that if the machine was not powered on when the regularly scheduled run would take place, a snapshot would be made next time the script is run.
Also deletes old snapshots after `btrfs send | btrfs receive` is done.
No snapshots are deleted unless there are at least 2 remaining.
My setup takes a snapshot every Saturday, checks every 3 hours (at the bottom of the hour) to make sure the snapshots aren't out of date, and deletes snapshots that are > 5 weeks old.

 * `SRC_SNAPSHOTS` is the path to the main snapshot subvolume
 * `DEST_SNAPSHOTS` is the path to the backup snapshot subvolume (prefarably on a separate storage medium)
 * `SUBVOLUMES` is an associative array of `[path] -> [subvolume name]` to describe what needs to be snapshotted
 * `NAME` is the name given to a snapshot
    * Must be unique each time a snapshot is taken
    * Must be sortable in chronological order by name
 * `DESIRED_PREV` is the name that would have been given to the snapshot during a regular run
    * Used to compare with the latest existing snapshot
    * Sets the frequency that snapshots will be made
 * `EXPIRED` is the name of the oldest snapshot you want to keep on the main snapshot volume

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


<!-- link refs -->
[yubikey]: https://github.com/xxc3nsoredxx/xxc3nsoredxx/tree/master/yubikey_linux_2fa
