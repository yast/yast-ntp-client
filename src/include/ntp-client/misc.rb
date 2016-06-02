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

    # Ask user if exit without saving
    # @return [Boolean] true if exit
    def reallyExit
      # yes-no popup
      !NtpClient.modified ||
        Popup.YesNo(_("Really exit?\nAll changes will be lost."))
    end

    def reallyExitSimple
      if NtpClient.run_service ==
          (UI.QueryWidget(Id("start"), :CurrentButton) == "boot") &&
          Ops.get_string(NtpClient.selected_record, "address", "") ==
              UI.QueryWidget(Id("server_address"), :Value)
        return true
      end
      reallyExit
    end

    def reallyExitComplex
      pol = ""
      if UI.QueryWidget(Id("policy_combo"), :Value) == :auto
        pol = "auto"
      elsif UI.QueryWidget(Id("policy_combo"), :Value) == :custom
        pol = Convert.to_string(UI.QueryWidget(Id("custom_policy"), :Value))
      end

      if NtpClient.run_service ==
          (UI.QueryWidget(Id("start"), :CurrentButton) == "boot") &&
          NtpClient.run_chroot == UI.QueryWidget(Id("run_chroot"), :Value) &&
          NtpClient.ntp_policy == pol &&
          !CWMFirewallInterfaces.OpenFirewallModified("firewall") &&
          !@sync_record_modified
        return true
      end
      @sync_record_modified = true
      reallyExit
    end

    # Restart the NTP daemon service
    def restartNtpDaemon
      Service.RunInitScript(NtpClient.service_name, "restart")

      nil
    end

    # Write the NTP settings without displaying progress
    def silentWrite
      progress_orig = Progress.set(false)
      NtpClient.Write
      Progress.set(progress_orig)

      nil
    end

    # Parse string to map of options
    # @param [String] options_string string of options
    # @param [Array<String>] with_param a list of options that must have a parameter
    # @param [Array<String>] without_param a list of options that don't have any parameter
    # @return [Hash] options as a map
    def string2opts(options_string, with_param, without_param)
      with_param = deep_copy(with_param)
      without_param = deep_copy(without_param)
      l = Builtins.splitstring(options_string, " ")
      l = Builtins.filter(l) { |e| e != "" }
      ignore_next = false
      index = -1
      unknown = []
      ret = Builtins.listmap(l) do |e|
        index = Ops.add(index, 1)
        if ignore_next
          ignore_next = false
          next { e => nil }
        end
        ignore_next = false
        if Builtins.contains(with_param, e)
          ignore_next = true
          next { e => Ops.get(l, Ops.add(index, 1), "") }
        elsif Builtins.contains(without_param, e)
          next { e => true }
        else
          unknown = Builtins.add(unknown, e)
          next { e => nil }
        end
      end
      ret = Builtins.filter(ret) { |_k, v| !v.nil? }
      ret = { "parsed" => ret, "unknown" => Builtins.mergestring(unknown, " ") }
      deep_copy(ret)
    end

    # Create options string from a map
    # @param [Hash{String => Object}] options a map options represented as a map
    # @param [String] other string other options that were set as string
    # @return [String] options represented as a string
    def opts2string(options, other)
      options = deep_copy(options)
      ret = other
      Builtins.foreach(options) do |k, v|
        if v == true
          ret = Builtins.sformat("%1 %2", ret, k)
        elsif v != false && v != ""
          ret = Builtins.sformat("%1 %2 %3", ret, k, v)
        end
      end
      ret
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

    # Set the clock type into an IP address
    # @param [String] address string the IP address to patch the clock number into
    # @param [Fixnum] clock_type integer the clock type to be set
    # @return [String] IP address with clock type set correctly
    def setClockType(address, clock_type)
      address = "127.127.0.0" if address == ""
      if !IP.Check4(address)
        Builtins.y2error("Invalid address: %1", address)
        return nil
      end
      ret = Builtins.regexpsub(
        address,
        "([0-9]+.[0-9]+.)[0-9]+(.[0-9]+)",
        Builtins.sformat("\\1%1\\2", clock_type)
      )
      ret
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

    # Set the clock unit number into an IP address
    # @param [String] address string the IP address to patch the clock number into
    # @param [Fixnum] unit_number integer the unit number to be set
    # @return [String] IP address with unit number set correctly
    def setClockUnitNumber(address, unit_number)
      address = "127.127.0.0" if address == ""
      if !IP.Check4(address)
        Builtins.y2error("Invalid address: %1", address)
        return nil
      end
      ret = Builtins.regexpsub(
        address,
        "([0-9]+.[0-9]+.[0-9]+.)[0-9]+",
        Builtins.sformat("\\1%1", unit_number)
      )
      ret
    end

    # Get entries for the clock type combo box
    # @return [Array] of items for the combo box
    def getClockTypesCombo
      clock_names = Builtins.mapmap(@clock_types) do |k, v|
        { k => Ops.get(v, "name", "") }
      end
      ret = Builtins.maplist(clock_names) do |k, v|
        [Builtins.sformat("%1", k), v]
      end
      deep_copy(ret)
    end

    # Propose the interface to be allowed for access in firewall
    # At the moment not used
    def proposeInterfacesToAllowAccess
      recs = NtpClient.getSyncRecords
      recs = Builtins.filter(recs) do |r|
        Ops.get_string(r, "type", "") == "peer" ||
          Ops.get_string(r, "type", "") == "broadcastclient"
      end
      addresses = Builtins.maplist(recs) { |r| Ops.get_string(r, "address", "") }
      addresses = Builtins.filter(addresses) { |a| a != "" && !a.nil? }
      addresses = Builtins.maplist(addresses) do |a|
        next a if IP.Check4(a)
        m = Convert.to_map(
          SCR.Execute(
            path(".target.bash_output"),
            Builtins.sformat("/usr/bin/host %1 | /bin/grep address", a)
          )
        )
        next nil if Ops.get_integer(m, "exit", 0) != 0
        out = Ops.get_string(m, "stdout", "")
        out = Builtins.regexpsub(out, "has address (.*)$", "\\1")
        out
      end
      addresses = Builtins.filter(addresses) { |a| a != "" && !a.nil? }
      ifaces = Builtins.maplist(addresses) do |a|
        m = Convert.to_map(
          SCR.Execute(
            path(".target.bash_output"),
            Builtins.sformat("/sbin/ip route get %1", a)
          )
        )
        next nil if Ops.get_integer(m, "exit", 0) != 0
        out = Ops.get_string(m, "stdout", "")
        out = Builtins.mergestring(Builtins.splitstring(out, "\n"), " ")
        out = Builtins.regexpsub(out, "dev[ ]+([^ ]+)[ ]+src", "\\1")
        out
      end
      ifaces = Builtins.toset(ifaces)
      ifaces = Builtins.filter(ifaces) { |i| !i.nil? }
      deep_copy(ifaces)
    end
  end
end
