# encoding: utf-8

# File:	include/ntp-client/helps.ycp
# Package:	Configuration of ntp-client
# Summary:	Help texts of all the dialogs
# Authors:	Jiri Srain <jsrain@suse.cz>
#
# $Id$
module Yast
  module NtpClientHelpsInclude
    Yast.import "NtpClient"
    def initialize_ntp_client_helps(_include_target)
      textdomain "ntp-client"

      # All helps are here
      @HELPS = {
        # Read dialog help 1/2
        "read"  => _(
          "<p><b><big>Initializing NTP Client Configuration</big></b><br>\nPlease wait...<br></p>"
        ) +
          # Read dialog help 2/2
          _(
            "<p><b><big>Aborting Initialization:</big></b><br>\n" \
            "Safely abort the configuration utility by pressing <b>Abort</b> now.</p>"
          ),
        # Write dialog help 1/2
        "write" => _(
          "<p><b><big>Saving NTP Client Configuration</big></b><br>\nPlease wait...<br></p>"
        ) +
          # Write dialog help 2/2
          _(
            "<p><b><big>Aborting Saving:</big></b><br>\n"           \
            "Abort the save procedure by pressing  <b>Abort</b>.\n" \
            "An additional dialog will inform you whether it is safe to do so.</p>"
          )
      }
    end
  end
end
