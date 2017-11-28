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
  module NtpClientDialogsInclude
    def initialize_ntp_client_dialogs(include_target)
      textdomain "ntp-client"

      Yast.import "CWM"
      Yast.import "CWMTab"
      Yast.import "Label"
      Yast.import "NtpClient"
      Yast.import "Popup"
      Yast.import "Stage"
      Yast.import "SuSEFirewall"
      Yast.import "Wizard"
      Yast.import "Report"
      Yast.import "Confirm"

      Yast.include include_target, "ntp-client/misc.rb"

      @widgets = nil
    end

    # Display the popup to confirm abort
    # @return [Boolean] true if confirmed
    def abortPopup
      Popup.ReallyAbort(true)
    end

    # Read settings dialog
    # @return `abort if aborted and `next otherwise
    def ReadDialog
      Wizard.RestoreHelp(Ops.get_string(@HELPS, "read", ""))

      # checking for root permissions (#158483)
      return :abort if !Stage.initial && !Confirm.MustBeRoot

      NtpClient.AbortFunction = fun_ref(method(:PollAbort), "boolean ()")
      ret = NtpClient.Read
      NtpClient.AbortFunction = nil
      ret ? :next : :abort
    end

    # Write settings dialog
    # @return `abort if aborted and `next otherwise
    def WriteDialog
      return :next if Stage.initial

      Wizard.RestoreHelp(Ops.get_string(@HELPS, "write", ""))
      NtpClient.AbortFunction = fun_ref(method(:PollAbort), "boolean ()")
      ret = NtpClient.Write
      NtpClient.AbortFunction = nil
      ret ? :next : :abort
    end
  end
end
