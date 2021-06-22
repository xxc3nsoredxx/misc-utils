# -*- autoconf -*-
# Process this file with autoconf to produce a configure script.

# TODO: Autotoolize the udev rule to specify configurable crypt name

m4_define([misc-utils-VERSION], [0.1])
AC_PREREQ([2.69])
AC_INIT([xxc3nsoredxx Miscellaneous Utilities],
    m4_defn([misc-utils-VERSION]),
    [https://github.com/xxc3nsoredxx/misc-utils/issues],
    [misc-utils])
AC_CONFIG_SRCDIR([snapshots/snapshots.sh.in])

# use --program-transform-name='<sed program>'
# eg. --program-transform-name='s/.sh$//' to remove .sh suffix
AC_ARG_PROGRAM

AC_ARG_ENABLE([snapshots],
    [AS_HELP_STRING([--enable-snapshots],
        [Enables the BTRFS snapshot management scripts])],
    [want_snapshots="$enableval"],
    [want_snapshots="yes"])

AM_CONDITIONAL([WANT_SNAPSHOTS],
    [test "x$want_snapshots" = "xyes"])

AM_INIT_AUTOMAKE([foreign subdir-objects -Wall -Werror])
AC_CONFIG_FILES([Makefile])
AC_CONFIG_FILES([snapshots/Makefile])

# Warn if nothing is enabled
AS_CASE(["x$want_snapshots"],
    [x*yes*], [],
    [AC_MSG_WARN([nothing selected for build/install])])

AC_OUTPUT
