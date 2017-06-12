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
        "guihandler" => fun_ref(method(:GuiHandler), "boolean ()"),
        "initialize" => fun_ref(NtpClient.method(:Read), "boolean ()"),
        "finish"     => fun_ref(NtpClient.method(:Write), "boolean ()"),
        "actions"    => {
          "status"  => {
            "handler" => fun_ref(method(:NtpStatusHandler), "boolean (map)"),
            # command line help text for an action
            "help"    => _(
              "Print the status of the NTP daemon"
            )
          },
          "list"    => {
            "handler" => fun_ref(method(:NtpListHandler), "boolean (map)"),
            # command line help text for an action
            "help"    => _(
              "Print all configured synchronization relationships"
            )
          },
          "enable"  => {
            "handler" => fun_ref(method(:NtpEnableHandler), "boolean (map)"),
            # command line help text for an action
            "help"    => _(
              "Enable the NTP daemon"
            )
          },
          "disable" => {
            "handler" => fun_ref(method(:NtpDisableHandler), "boolean (map)"),
            # command line help text for an action
            "help"    => _(
              "Disable the NTP daemon"
            )
          },
          "add"     => {
            "handler" => fun_ref(method(:NtpAddHandler), "boolean (map)"),
            # command line help text for an action
            "help"    => _(
              "Add new synchronization relationship"
            )
          },
          "edit"    => {
            "handler" => fun_ref(method(:NtpEditHandler), "boolean (map)"),
            # command line help text for an action
            "help"    => _(
              "Edit existing synchronization relationship"
            )
          },
          "delete"  => {
            "handler" => fun_ref(method(:NtpDeleteHandler), "boolean (map)"),
            # command line help text for an action
            "help"    => _(
              "Delete a synchronization relationship"
            )
          }
        },
        "options"    => {
          "server"          => {
            # command line help text for an option
            "help" => _(
              "The address of the server"
            ),
            "type" => "string"
          },
          "peer"            => {
            # command line help text for an option
            "help" => _(
              "The address of the peer"
            ),
            "type" => "string"
          },
          "broadcast"       => {
            # command line help text for an option
            "help" => _(
              "The address to which to broadcast"
            ),
            "type" => "string"
          },
          "broadcastclient" => {
            # command line help text for an option
            "help" => _(
              "The address from which to accept broadcasts"
            ),
            "type" => "string"
          },
          "options"         => {
            # command line help text for an option
            "help" => _(
              "The options of the relationship"
            ),
            "type" => "string"
          },
          "fudge"           => {
            # command line help text for an option
            "help" => _(
              "Options for clock driver calibration"
            ),
            "type" => "string"
          },
          "initial"         => {
            # command line help text for an option
            "help" => _(
              "Use the server for initial synchronization"
            )
          },
          "no-initial"      => {
            # command line help text for an option
            "help" => _(
              "Do not use the server for initial synchronization"
            )
          }
        },
        "mappings"   => {
          "status"  => [],
          "list"    => [],
          "enable"  => [],
          "disable" => [],
          "add"     => [
            "server",
            "peer",
            "broadcast",
            "broadcastclient",
            "options",
            "fudge",
            "initial"
          ],
          "edit"    => [
            "server",
            "peer",
            "broadcast",
            "broadcastclient",
            "options",
            "fudge",
            "initial",
            "no-initial"
          ],
          "delete"  => ["server", "peer", "broadcast", "broadcastclient"]
        }
      }
    end

    # Get the type of the synchronization record
    # @param [Hash] options a map of the command line options
    # @return [String] the sync record type
    def getSyncRecordType(options)
      options = deep_copy(options)
      type = ""
      if Builtins.haskey(options, "server")
        type = "server"
      elsif Builtins.haskey(options, "peer")
        type = "peer"
      elsif Builtins.haskey(options, "broadcast")
        type = "broadcast"
      elsif Builtins.haskey(options, "broadcastclient")
        type = "broadcastclient"
      end
      type
    end

    # Find the synchronization record the map is about
    # @param [Hash] options map of command line options
    # @return index of the found record, -1 in case of an error
    def findSyncRecord(options)
      options = deep_copy(options)
      type = getSyncRecordType(options)
      if type == ""
        # error report for command line
        CommandLine.Print(_("The synchronization peer not specified."))
        return -1
      end
      address = Ops.get_string(options, type, "")
      index = NtpClient.findSyncRecord(type, address)
      if index == -1
        # error report for command line
        CommandLine.Print(_("Specified synchronization peer not found."))
        return -1
      end
      index
    end

    # Update the synchronization record
    # @param [Hash] options map of command line options
    # @return [Boolean] true on success
    def updateSyncRecord(options)
      options = deep_copy(options)
      type = Ops.get_string(NtpClient.selected_record, "type", "")
      if type == ""
        type = getSyncRecordType(options)
        Ops.set(NtpClient.selected_record, "type", type)
      end
      if Builtins.haskey(options, type)
        Ops.set(
          NtpClient.selected_record,
          "address",
          Ops.get_string(options, type, "")
        )
      end
      if Builtins.haskey(options, "options")
        Ops.set(
          NtpClient.selected_record,
          "options",
          Ops.get_string(options, "options", "")
        )
      end
      if Builtins.haskey(options, "fudge")
        Ops.set(
          NtpClient.selected_record,
          "fudge_options",
          Ops.get_string(options, "fudge", "")
        )
      end
      if Builtins.haskey(options, "initial")
        Builtins.y2warning("option 'initial' is obsolete")
      end
      if Builtins.haskey(options, "no-initial")
        Builtins.y2warning("option 'no-initial' is obsolete")
      end
      NtpClient.storeSyncRecord
    end

    # Handler for command line interface
    # @param [Hash] options map options from the command line
    # @return [Boolean] true if settings have been changed
    def NtpStatusHandler(_options)
      CommandLine.Print(
        # status information for command line
        NtpClient.run_service ? _("NTP daemon is enabled.") : _("NTP daemon is disabled.")
      )
      false
    end

    # Handler for command line interface
    # @param [Hash] options map options from the command line
    # @return [Boolean] true if settings have been changed
    def NtpListHandler(_options)
      # FIXME: there is some code duplication with the initialization handler of the
      # overview widget
      types = {
        # table cell, NTP relationship type
        "server"          => _("Server"),
        # table cell, NTP relationship type
        "peer"            => _("Peer"),
        # table cell, NTP relationship type
        "broadcast"       => _("Broadcast"),
        # table cell, NTP relationship type
        "broadcastclient" => _(
          "Accepting Broadcasts"
        )
      }
      Builtins.foreach(NtpClient.getSyncRecords) do |i|
        type = Ops.get_string(i, "type", "")
        address = Ops.get_string(i, "address", "")
        if type == "__clock"
          clock_type = getClockType(address)
          unit_number = getClockUnitNumber(address)
          device = Ops.get_string(i, "device", "")
          if device == ""
            # table cell, %1 is integer 0-3
            device = Builtins.sformat(_("Unit Number: %1"), unit_number)
          end
          device = "" if clock_type == 1 && unit_number == 0
          clock_name = Ops.get(@clock_types, [clock_type, "name"], "")
          if clock_name == ""
            # table cell, NTP relationship type
            clock_name = _("Local Radio Clock")
          end
          CommandLine.Print(Builtins.sformat("%1 %2", clock_name, device))
        else
          CommandLine.Print(
            Builtins.sformat("%1 %2", Ops.get_string(types, type, ""), address)
          )
        end
      end
      false
    end

    # Handler for command line interface
    # @param [Hash] options map options from the command line
    # @return [Boolean] true if settings have been changed
    def NtpEnableHandler(_options)
      NtpClient.modified = !NtpClient.run_service
      NtpClient.run_service = true
      true
    end

    # Handler for command line interface
    # @param [Hash] options map options from the command line
    # @return [Boolean] true if settings have been changed
    def NtpDisableHandler(_options)
      NtpClient.modified = NtpClient.run_service
      NtpClient.run_service = false
      true
    end

    # Handler for command line interface
    # @param [Hash] options map options from the command line
    # @return [Boolean] true if settings have been changed
    def NtpAddHandler(options)
      options = deep_copy(options)
      NtpClient.selectSyncRecord(-1)
      updateSyncRecord(options)
    end

    # Handler for command line interface
    # @param [Hash] options map options from the command line
    # @return [Boolean] true if settings have been changed
    def NtpEditHandler(options)
      options = deep_copy(options)
      index = findSyncRecord(options)
      return false if Ops.less_than(index, 0)
      if !NtpClient.selectSyncRecord(index)
        # command line error message
        CommandLine.Print(_("Reading the settings failed."))
        return false
      end
      updateSyncRecord(options)
    end

    # Handler for command line interface
    # @param [Hash] options map options from the command line
    # @return [Boolean] true if settings have been changed
    def NtpDeleteHandler(options)
      options = deep_copy(options)
      index = findSyncRecord(options)
      return false if Ops.less_than(index, 0)
      NtpClient.deleteSyncRecord(index)
      true
    end
  end
end
