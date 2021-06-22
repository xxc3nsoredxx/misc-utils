# misc-utils
A collection of miscellaneous little utils that I don't feel deserve a full repo.

### Autotoolization in progress
This repo is slowly being packaged by Autotools.

**Note:** All of the following utils present in the repo or tarball in their final form are configured to use the `/usr/local` prefix with the exception of `--sysconfdir=/etc`.
If installing using Autotools, make sure to specify the system config directory.

Currently autotoolized:
 * snapshots

### Installing
Run:
```bash
./configure --sysconfdir=PATH_TO_SYSTEM_CONFIG_DIR
make
make install
```

By default all utils are enabled and will be built/installed.
To selectively leave out `util` run:
```bash
./configure --disable-util
```

The relevant option for each util is listed in its description below.
Alternatively, to see a full list of configure options run:
```bash
./configure --help
```

### ebuild in progress
The whole reason for autotoolizing the repo is that I can write a nice ebuild for it.

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
A bash script for managing BTRFS snapshots.
Has two modes: one for taking snapshots and one for transfering snapshots.
Various options can be set in the [`snapshots.conf` config file][snapshots config].

### Taking snapshots
Initiated with the `-s` option.

Takes a snapshot of the configured subvolumes and uses `btrfs send | btrfs receive` to transfer them to a separate drive.
Determines if incremental send is used based on the number of existing snapshots of a given subvolume.
Assumes that the destination has _at least_ the same snapshots as the source.

The default format for snapshot names is `YYYY-MM-DD`.
Designed to be run at regular intervals in a cron job.
The script can be run repeatedly to trivially verify that snapshots have been taken.
If the regularly scheduled snapshot was missed, the next run will make up for it.
Also has trivial facilities for keeping the snapshots in sync.
It will check to see if the most recent snapshot on the destination is the same as the one on the source.
If the source has a newer snapshot, it will be sent to the destination.

Snapshots older than the configured expiration threshold will be deleted from the source in order to save space.
No snapshots are deleted unless at least 2 exist so that incremental send will continue to function nicely.

My setup takes a snapshot after every Saturday, checks every 3 hours (at the bottom of the hour) to make sure the snapshots aren't out of date, and deletes snapshots that are > 5 weeks old.

### Transfering snapshots
Initiated with the `-t` option.

Transfers snapshots from one drive to another.
The destination drive is encrypted using LUKS.
The accompanying `udev` rule creates a symlink called `/dev/ss_crypt` pointing to the partition with the LUKS container.

Snapshots older than the cutoff will be moved, automatically determining the appropriate base snapshot based on what exists on the destination.
The moved snapshot is then deleted from the source drive.
The exception being the most recent snapshot older than the cutoff.
This one is retained in order to maintain a common base between the source and destination drives for incremental send.

### Requirements (general)
* Must be run as root
* `sys-fs/btrfs-progs`

### Requirements (transfer mode)
* An implementation of `udev`
* `sys-fs/cryptsetup`
* A drive set up with BTRFS in a LUKS2 container
* Encrypted using a key-file instead of password input
* `SS_CRYPT` as the label given in the LUKS2 header

### Configure options
* `--enable-snapshots`

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
[snapshots config]: snapshots/snapshots.conf
[outlook redir]: https://github.com/xxc3nsoredxx/misc-utils/raw/master/userscripts/outlook_logout_redirect.user.js
