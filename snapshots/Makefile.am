dist_bin_SCRIPTS = snapshots.sh
# Automake creates configdir/udevdir variables from AC_SUBST in configure.ac
dist_config_DATA = snapshots.conf
dist_udev_DATA = 99-ss_crypt.rules

CLEANFILES = $(dist_bin_SCRIPTS)
EXTRA_DIST = snapshots.sh.in 99-ss_crypt.rules

edit = sed \
	-e 's|@configdir[@]|$(configdir)|g'

snapshots.sh: $(srcdir)/snapshots.sh.in Makefile
	rm -f $@ $@.tmp
	srcdir=''; \
	  test -f ./$@.in || srcdir=$(srcdir)/; \
	  $(edit) $${srcdir}$@.in > $@.tmp
	chmod +x $@.tmp
	chmod a-w $@.tmp
	mv $@.tmp $@
