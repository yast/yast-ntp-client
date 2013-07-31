# Sources for ntp-client

module_DATA = \
  modules/NtpClient.rb

client_DATA = \
  clients/ntp-client.rb \
  clients/ntp-client_auto.rb \
  clients/ntp-client_finish.rb \
  clients/ntp-client_proposal.rb

yncludedir = @yncludedir@/ntp-client
ynclude_DATA = \
  include/ntp-client/widgets.rb \
  include/ntp-client/wizards.rb \
  include/ntp-client/commandline.rb \
  include/ntp-client/misc.rb \
  include/ntp-client/dialogs.rb \
  include/ntp-client/helps.rb \
  include/ntp-client/clocktypes.rb

scrconf_DATA = \
  scrconf/cfg_ntp.scr \
  scrconf/etc_ntp.scr

schemafilesdir = $(schemadir)/autoyast/rnc
schemafiles_DATA = \
  autoyast-rnc/ntpclient.rnc

ydata_DATA = \
  data/ntp_servers.ycp

desktop_DATA = \
  desktop/ntp-client.desktop

EXTRA_DIST = $(module_DATA) $(client_DATA) $(ynclude_DATA) $(scrconf_DATA) $(schemafiles_DATA) $(ydata_DATA) $(desktop_DATA)

include $(top_srcdir)/Makefile.am.common