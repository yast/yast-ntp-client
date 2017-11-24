# encoding: utf-8

# File:	include/ntp-client/misc.ycp
# Package:	Configuration of ntp-client
# Summary:	Miscelanous functions for configuration of ntp-client.
# Authors:	Jiri Srain <jsrain@suse.cz>
#
# $Id$
module Yast
  module NtpClientMiscInclude
    def initialize_ntp_client_misc(include_target)
      Yast.import "UI"

      textdomain "ntp-client"

      Yast.import "CWMFirewallInterfaces"
      Yast.import "IP"
      Yast.import "Popup"
      Yast.import "Progress"
      Yast.import "Service"
      Yast.import "NtpClient"

      Yast.include include_target, "ntp-client/clocktypes.rb"

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

    # Get the type of the clock from the address
    # @param [String] address string the clock identification in the IP address form
    # @return [Fixnum] the clock type
    def getClockType(address)
      return 0 if address == ""
      if !IP.Check4(address)
        Builtins.y2error("Invalid address: %1", address)
        return nil
      end
      cl_type = Builtins.regexpsub(
        address,
        "[0-9]+.[0-9]+.([0-9]+).[0-9]+",
        "\\1"
      )
      Builtins.tointeger(cl_type)
    end

    # Get the unit number of the clock from the address
    # @param [String] address string the clock identification in the IP address form
    # @return [Fixnum] the unit number
    def getClockUnitNumber(address)
      return 0 if address == ""
      if !IP.Check4(address)
        Builtins.y2error("Invalid address: %1", address)
        return nil
      end
      cl_type = Builtins.regexpsub(
        address,
        "[0-9]+.[0-9]+.[0-9]+.([0-9]+)",
        "\\1"
      )
      Builtins.tointeger(cl_type)
    end
  end
end
