# encoding: utf-8

# File:	clients/ntp-client.ycp
# Package:	Configuration of ntp-client
# Summary:	Main file
# Authors:	Jiri Srain <jsrain@suse.cz>
#
# $Id$
#
# Main file for ntp-client configuration. Uses all other files.
module Yast
  module NtpClientCommandlineInclude
    def initialize_ntp_client_commandline(_include_target)
      Yast.import "CommandLine"
      Yast.import "NtpClient"

      textdomain "ntp-client"

      @cmdline = {
        "id"         => "ntp-client",
        # command line help text for NTP client module
        "help"       => _(
          "NTP client configuration module."
        ),
        "guihandler" => fun_ref(method(:GuiHandler), "boolean ()")
      }
    end
  end
end
