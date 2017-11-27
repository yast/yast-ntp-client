# encoding: utf-8

# File:	include/ntp-client/misc.ycp
# Package:	Configuration of ntp-client
# Summary:	Miscelanous functions for configuration of ntp-client.
# Authors:	Jiri Srain <jsrain@suse.cz>
#
# $Id$
module Yast
  module NtpClientMiscInclude
    def initialize_ntp_client_misc(_include_target)
      Yast.import "UI"

      textdomain "ntp-client"

      Yast.import "CWMFirewallInterfaces"
      Yast.import "IP"
      Yast.import "Popup"
      Yast.import "Progress"
      Yast.import "Service"
      Yast.import "NtpClient"

      # FIXME: this is quite ugly ... the whole checkinf if something was changed
      # ... but it works :-)
      @sync_record_modified = false
    end

    # If modified, ask for confirmation
    # @return true if abort is confirmed
    def ReallyAbort
      !NtpClient.modified || Popup.ReallyAbort(true)
    end

    # Check for pending Abort press
    # @return true if pending abort
    def PollAbort
      UI.PollInput == :abort
    end
  end
end
