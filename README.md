# misc-utils
A collection of miscellaneous little utils that I don't feel deserve a full repo.

## cross\_arm
Creates an ARM cross-compiler toolchain.
Originally created for a class that dealt with ARM binaries in some assignments.
Should work for Raspberry Pi's since that's what the assignment test server was running (don't remember which model).
Definitely works for compiling against QEMU's ARM userspace emulation since that's what I used to test my code locally.

Adapting the script for other architectures should only require changing the `TARGET*` and `CONF_*` variables.

The toolchain is installed into an overlay called `cross-$TARGET` and each tool is installed as `$TARGET-*`.
For example, the version of GCC which is installed can be invoked using `$TARGET-gcc`.

### Requirements
 * Must be run as root
 * `sys-devel/crossdev`
 * `app-portage/gentoolkit`
   * Uses `equery(1)` to determine existing package version

## genhash
Creates an `/etc/shadow`-friendly SHA-512 hash given a password and a salt.
`crypt(3)` allows for up to 16 characters in the salt from the character set `[a-zA-Z0-9./]`.
A salt argument longer than 16 characters gets truncated down, and invalid characters get converted into '.'.
To compile, just run `make` in the `genhash/` directory.

```
Usage: genhash [password] [salt]
```

## only\_required\_firmware
A bash script to filter the config file for the Gentoo package `sys-kernel/linux-firmware`.
Parses the output of `modinfo` for each module given by `lsmod` for required firmware files.
I recommend rebooting after updating the package so that any new firmware files get loaded and are found by the script.
Re-emerges the package at the end (which will clean up any installed but unused firmware files from the system).

### Requirements
 * Must be run as root
 * `savedconfig` USE flag for `sys-kernel/linux-firmware` is set

## root\_lock
If root is logged in, locks the machine requiring the root password to unlock.
Works for physical logins as well as `su(1)`.
Companion script for [locking the machine when my Yubikey is removed][yubikey].

### Requirements
 * Must be run as root
   * Designed to be run as part of a system service

## snapshots
A set of bash scripts for managing BTRFS snapshots.
These scripts must be run as root.

### snapshots.sh
Takes snapshots of a BTRFS filesystem.
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

### transfer.sh
Transfers snapshots from one drive to another.
The destination drive is encrypted using LUKS.
The accompanying `udev` rule creates a symlink called `/dev/ss_crypt` pointing to the partition with the LUKS container.
Snapshots older than `OLDEST_CUTOFF` will be moved, automatically determining the appropriate base snapshot based on what exists on the destination, and deleting moved snapshots from the source.
The most recent snapshot older than the cutoff will be retained in order to maintain a common base between the source and destination drives.

The following variables can be set in `transfer.conf`:
* `SRC_SNAPSHOTS_DEV`
* `SRC_SNAPSHOTS`
* `SRC_MOUNT_OPTS`
* `DEST_SNAPSHOTS`
* `DEST_MOUNT_OPTS`
* `LUKS_KEYFILE`
* `SUBVOLUMES`
* `OLDEST_CUTOFF`

Pre-requisites:
* A drive set up with BTRFS in a LUKS2 container
* `SS_CRYPT` as the label of the LUKS device
* Encrypted using a key-file instead of password input
* Snapshots named in a sortable fashion
    * This and `snapshots.sh` use `date(1)` for naming

## userscripts
A collection of scripts loaded into [Greasemonkey](https://www.greasespot.net).

### mobile\_to\_desktop
Redirects a mobile page to a desktop page.
Inspired by all the people on Reddit posting links to https://en.m.wikipedia.org which, for some reason, doesn't go to the desktop page on desktop browsers.
The other way around works just fine -- desktop Wikipedia on a mobile browser redirects to mobile Wikipedia.
Currently only has Wikipedia listed in the URLs to convert.
More will be added if/as needed.

You can use the Wikipedia link above to conveniently test the script after installation.
A completely unintentional side effect of the link automatically being generated for the text.

[Click here to install the userscript](https://github.com/xxc3nsoredxx/misc-utils/raw/master/userscripts/mobile_to_desktop.user.js)

### outlook\_logout\_redirect
Sometimes the Outlook session will be automatically logged out.
When this happens, going to Outlook instead gives an annoying page that says "You signed out of your account."
This requires going _back to the address bar_ to enter the Outlook URL again which will go to the login page.

This userscript automatically redirects to Outlook when the annoying page is detected.

[Click here to install the userscript][outlook redir]


<!-- link refs -->
[yubikey]: https://github.com/xxc3nsoredxx/xxc3nsoredxx/tree/master/yubikey_linux_2fa
[outlook redir]: https://github.com/xxc3nsoredxx/misc-utils/raw/master/userscripts/outlook_logout_redirect.user.js
