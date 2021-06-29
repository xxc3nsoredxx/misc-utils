dist_sbin_SCRIPTS = snapshots.sh
# Automake creates directory variables from AC_SUBST in configure.ac
dist_config_DATA = snapshots.conf
dist_cron_DATA = snapshots.cron
dist_udev_DATA = 99-ss_crypt.rules

dist_noinst_SCRIPTS = gen_cron.sh

CLEANFILES  = $(dist_sbin_SCRIPTS)
CLEANFILES += $(dist_cron_DATA)
CLEANFILES += $(noinst_SCRIPTS)

EXTRA_DIST  = snapshots.sh.in
EXTRA_DIST += 99-ss_crypt.rules

edit = sed \
	-e 's|@configdir[@]|$(configdir)|g'

snapshots.cron: gen_cron.sh snapshots.conf Makefile
	rm -f $@
	./gen_cron.sh $@

snapshots.sh: $(srcdir)/snapshots.sh.in Makefile
	rm -f $@ $@.tmp
	srcdir=''; \
	  test -f ./$@.in || srcdir=$(srcdir)/; \
	  $(edit) $${srcdir}$@.in > $@.tmp
	chmod +x $@.tmp
	chmod a-w $@.tmp
	mv $@.tmp $@
