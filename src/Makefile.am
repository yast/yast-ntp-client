#
# Makefile.am for devtools/devtools/skeletons/config/src
#

YCPCFLAGS = -I .

yncludedir = @yncludedir@/ntp-client

client_DATA =			\
	ntp-client.ycp		\
	ntp-client_auto.ycp

ynclude_DATA =			\
	helps.ycp		\
	wizards.ycp		\
	dialogs.ycp		\
	widgets.ycp		\
	misc.ycp		\
	clocktypes.ycp

config_DATA =			\
	ntp-client.y2cc

desktop_DATA =			\
	ntp-client.desktop

module_DATA =			\
	NtpClient.ycp

EXTRA_DIST = $(client_DATA) $(ynclude_DATA) $(config_DATA) $(module_DATA) $(desktop_DATA)


symlinks:
	test -L ntp-client || ln -sf . ntp-client

ycpchook = symlinks


include $(top_srcdir)/Makefile.am.common

