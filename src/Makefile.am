#
# Makefile.am for devtools/devtools/skeletons/config/src
#

YCPCFLAGS = -I .

yncludedir = @yncludedir@/ntp-client

client_DATA =			\
	ntp-client.ycp		\
	ntp-client_auto.ycp     \
        ntp-client_proposal.ycp \
        ntp-client_finish.ycp

ynclude_DATA =			\
	helps.ycp		\
	wizards.ycp		\
	dialogs.ycp		\
	widgets.ycp		\
	misc.ycp		\
	clocktypes.ycp		\
	commandline.ycp

desktop_DATA =			\
	ntp-client.desktop

module_DATA =			\
	NtpClient.ycp

rncdir= $(schemadir)/autoyast/rnc/
rnc_DATA =			\
	ntpclient.rnc

EXTRA_DIST = $(client_DATA) $(ynclude_DATA) $(module_DATA) $(desktop_DATA) $(rnc_DATA)


ntp-client:
	test -L ntp-client || ln -sf . ntp-client

ycpchook = ntp-client


include $(top_srcdir)/Makefile.am.common

