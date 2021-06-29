# -*- autoconf -*-
# Process this file with autoconf to produce a configure script.

# TODO: Autotoolize the udev rule to specify configurable crypt name

m4_define([misc-utils-VERSION], [0.1.1])
AC_PREREQ([2.69])
AC_INIT([xxc3nsoredxx Miscellaneous Utilities],
    m4_defn([misc-utils-VERSION]),
    [https://github.com/xxc3nsoredxx/misc-utils/issues],
    [misc-utils])
AC_CONFIG_SRCDIR([snapshots/snapshots.sh.in])

# use --program-transform-name='<sed program>'
# eg. --program-transform-name='s/.sh$//' to remove .sh suffix
AC_ARG_PROGRAM

AC_ARG_WITH([udevdir],
    [AS_HELP_STRING([--with-udevdir=DIR],
        [udev rules directory [SYSCONFDIR/udev/rules.d]])],
    [udevdir="$withval"],
    [udevdir='$(sysconfdir)/udev/rules.d'])
AS_CASE(["x$udevdir"],
    # Use default if udevdir is "yes" (ie, called with --with-udevdir)
    [xyes], [AC_MSG_WARN([no udev rules directory given in --with-udevdir, using default])]
            [udevdir='$(sysconfdir)/udev/rules.d'],
    # Use default if udevdir is empty (ie, called with --with-udevdir=)
    [x], [AC_MSG_WARN([empty udev rules directory given in --with-udevdir, using default])]
         [udevdir='$(sysconfdir)/udev/rules.d'],
    # Otherwise assume a good path is given
    [])
AC_SUBST([udevdir], [$udevdir])

AC_ARG_ENABLE([snapshots],
    [AS_HELP_STRING([--enable-snapshots],
        [Enables the BTRFS snapshot management scripts])],
    [want_snapshots="$enableval"],
    [want_snapshots="yes"])
AM_CONDITIONAL([WANT_SNAPSHOTS],
    [test "x$want_snapshots" = "xyes"])

AC_SUBST([configdir], ['$(sysconfdir)/misc-utils'])
AC_SUBST([crondir], ['$(sysconfdir)/cron.d'])

AM_INIT_AUTOMAKE([foreign subdir-objects -Wall -Werror])
AC_CONFIG_FILES([Makefile])
AC_CONFIG_FILES([snapshots/Makefile])
AC_CONFIG_FILES([snapshots/gen_cron.sh], [chmod +x snapshots/gen_cron.sh])

# Warn if nothing is enabled
AS_CASE(["x$want_snapshots"],
    [x*yes*], [],
    [AC_MSG_WARN([nothing selected for build/install])])

AC_OUTPUT
