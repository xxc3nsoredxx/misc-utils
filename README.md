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
