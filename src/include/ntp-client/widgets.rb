# encoding: utf-8

# File:	clients/ntp-client.ycp
# Package:	Configuration of ntp-client
# Summary:	Main file
# Authors:	Jiri Srain <jsrain@suse.cz>
#
# $Id$
#
# Main file for ntp-client configuration. Uses all other files.

require "tempfile"

module Yast
  module NtpClientWidgetsInclude
    include Logger

    def initialize_ntp_client_widgets(include_target)
      textdomain "ntp-client"

      Yast.import "Confirm"
      Yast.import "Popup"
      Yast.import "Label"
      Yast.import "LogView"
      Yast.import "SLPAPI"
      Yast.import "NetworkInterfaces"
      Yast.import "NetworkService"
      Yast.import "NtpClient"
      Yast.import "CWMFirewallInterfaces"
      Yast.import "Report"
      Yast.import "Hostname"
      Yast.import "IP"
      Yast.import "Progress"

      Yast.include include_target, "ntp-client/helps.rb"
      Yast.include include_target, "ntp-client/dialogs.rb"

      # selected type of peer
      @peer_type_selected = nil

      # List of NTP servers already found
      @found_servers_cache = nil

      # The 'Current Record' when NTP is being initialized, see bug 177575
      @selected_record_during_init = {}

      # if there was some server defined before pool_ntp_org was selected
      @ntp_server_before_random_servers = ""

      @last_country = nil
    end

    # Save the configuration and restart NTP deamon
    def SilentWrite
      orig_progress = Progress.set(false)
      ret = NtpClient.Write
      Progress.set(orig_progress)
      ret
    end

    # Show popup with NTP daemon's log
    def showLogPopup
      tmp_file = Tempfile.new("yast_chronylog")
      tmp_file.close
      begin
        SCR.Execute(path(".target.bash"), "/usr/bin/journalctl --boot --unit chronyd --no-pager --no-tail > '#{tmp_file.path}'")
        LogView.Display(
          "file"    => tmp_file.path,
          "save"    => true,
          "actions" => [
            # menubutton entry, try to keep short
            [
              _("Restart NTP Daemon"),
              fun_ref(method(:restartNtpDaemon), "void ()")
            ],
            # menubutton entry, try to keep short
            [
              _("Save Settings and Restart NTP Daemon"),
              fun_ref(method(:SilentWrite), "boolean ()")
            ]
          ]
        )
      ensure
        tmp_file.unlink
      end
      nil
    end

    # Handle function of the widget
    # @param [String] id string widget id
    # @param [Hash] event map event that caused storing process
    # @return [Symbol] always nil
    def ntpEnabledOrDisabled(id, event)
      event = deep_copy(event)
      ev_id = Ops.get(event, "ID")
      if ev_id == "boot" || ev_id == "never" || ev_id == "sync"
        enabled = UI.QueryWidget(Id("start"), :CurrentButton) != "never"
        UI.ChangeWidget(Id(id), :Enabled, enabled)
      end

      nil
    end

    # Handle function of the widget
    # @param [String] id string widget id
    # @param [Hash] event map event that caused storing process
    # @return [Symbol] always nil
    def timeSyncOrNo(id, event)
      event = deep_copy(event)
      ev_id = Ops.get(event, "ID")
      if ev_id == "boot" || ev_id == "never" || ev_id == "sync"
        enabled = UI.QueryWidget(Id("start"), :CurrentButton) == "sync"
        UI.ChangeWidget(Id(id), :Enabled, enabled)
      end

      nil
    end

    # Initialize the widget
    # @param [String] id any widget id
    def intervalInit(_id)
      UI.ChangeWidget(Id("interval"), :Value, NtpClient.sync_interval)

      enabled = UI.QueryWidget(Id("start"), :CurrentButton) == "sync"
      UI.ChangeWidget(Id("interval"), :Enabled, enabled)

      nil
    end

    # Store settings of the widget
    # @param [String] id any widget id
    # @param [Hash] event map event that caused storing process
    def intervalStore(_id, _event)
      NtpClient.sync_interval = Convert.to_integer(
        UI.QueryWidget(Id("interval"), :Value)
      )

      nil
    end

    # Initialize the widget
    # @param [String] id any widget id
    def startInit(_id)
      if NtpClient.synchronize_time
        UI.ChangeWidget(Id("start"), :CurrentButton, "sync")
      elsif NtpClient.run_service
        UI.ChangeWidget(Id("start"), :CurrentButton, "boot")
      else
        UI.ChangeWidget(Id("start"), :CurrentButton, "never")
      end

      nil
    end

    # Store settings of the widget
    # @param [String] id any widget id
    # @param [Hash] event map event that caused storing process
    def startStore(_id, _event)
      NtpClient.run_service = UI.QueryWidget(Id("start"), :CurrentButton) == "boot"
      NtpClient.synchronize_time = UI.QueryWidget(Id("start"), :CurrentButton) == "sync"

      nil
    end

    # Handle function of the widget
    # @param [String] id string widget id
    # @param [Hash] event map event that caused storing process
    # @return [Object] always nil
    def startHandle(_id, event)
      event = deep_copy(event)
      start = UI.QueryWidget(Id("start"), :CurrentButton) == "boot"
      # All these network devices are possibly started on boot || managed by NM
      # hence do not display the message
      d1 = NetworkInterfaces.Locate("STARTMODE", "onboot")
      d2 = NetworkInterfaces.Locate("STARTMODE", "auto")
      d3 = NetworkInterfaces.Locate("STARTMODE", "nfsroot")
      d4 = NetworkInterfaces.Locate("STARTMODE", "managed")

      devices = Convert.convert(
        Builtins.union(Builtins.union(d1, d2), Builtins.union(d3, d4)),
        from: "list",
        to:   "list <string>"
      )
      devices = Builtins.filter(devices) { |d| d != "lo" }
      # Do not display this warning if we use NetworkManager (#299666)
      if start && !NetworkService.is_network_manager && Builtins.size(devices) == 0 &&
          Ops.get_string(event, "EventReason", "") != "" && !Popup.ContinueCancel(
            _(
              "Warning!\n\n" \
              "If you do not have a permanent Internet connection,\n" \
              "starting the NTP daemon can take a very long time and \n" \
              "the daemon might not run properly."
            )
          )
        UI.ChangeWidget(Id("start"), :CurrentButton, "never")
      end

      if start != NtpClient.run_service
        Builtins.y2milestone(
          "set modified from %1 to true 1",
          NtpClient.modified
        )
        NtpClient.modified = true
      end

      if start
        CWMFirewallInterfaces.EnableOpenFirewallWidget
      else
        CWMFirewallInterfaces.DisableOpenFirewallWidget
      end

      if CWMFirewallInterfaces.OpenFirewallModified("firewall")
        NtpClient.change_firewall = true
      end

      nil
    end

    # Checks the current simple configuration filled in UI.
    # Selected option RandomPoolServers returns true;
    # Selected valid server address also returns true;
    #
    # @return [Boolean] whether the configuration is correct
    def CheckCurrentSimpleConfiguration(check_the_server)
      # if the option "random_servers" is selected, do not check the server name
      if UI.WidgetExists(Id("use_random_servers")) &&
          Convert.to_boolean(UI.QueryWidget(Id("use_random_servers"), :Value))
        return true
      end

      server_1 = Convert.to_string(UI.QueryWidget(Id("server_address"), :Value))
      if !check_the_server && server_1 == ""
        Builtins.y2milestone("Not checking an empty server...")
        return true
      end

      server_2 = server_1
      if Builtins.regexpmatch(server_2, "(.*).$")
        server_2 = Builtins.regexpsub(server_2, "(.*).$", "\\1")
      end

      if !Hostname.Check(server_1) && !Hostname.CheckFQ(server_1) && !IP.Check(server_1) &&
          !Hostname.Check(server_2) && !Hostname.CheckFQ(server_2)
        # TRANSLATORS: Popup error message
        Report.Error(
          Builtins.sformat(
            _(
              "NTP server '%1' is not a valid hostname,\nfully qualified hostname," \
              " IPv4 address, or IPv6 address."
            ),
            server_1
          )
        )
        return false
      end

      true
    end

    # Check the current confifuration and returns whether some server address is defined
    def ServerAddressIsInConfiguration
      ret = false
      rss = NtpClient.IsRandomServersServiceEnabled

      Builtins.foreach(NtpClient.ntp_records) do |one_record|
        # checking for server
        if Ops.get(one_record, "type") == "server"
          # RandomServersService is disabled
          if !rss
            ret = true
            raise Break
            # RandomServersService is enabled, don't take servers from RSS
          elsif !Builtins.contains(
            NtpClient.random_pool_servers,
            Ops.get_string(one_record, "address", "")
          )
            ret = true
            raise Break
          end
        end
      end

      ret
    end

    # Handle function of the widget
    # @param [String] key any widget id
    # @param [Hash] event map event that caused storing process
    # @return [Symbol] always `complex
    def complexButtonHandle(key, event)
      event = deep_copy(event)
      if event["ID"] == "complex_button"
        # true  - check and report the missing server value
        # false - the opposite
        handle_the_server = !UI.QueryWidget(Id("server_address"), :Value).to_s.empty?

        conf_check = CheckCurrentSimpleConfiguration(handle_the_server)
        log.info("Checking the current simple configuration returned: #{conf_check}")

        NtpClient.selected_record["address"] = UI.QueryWidget(Id("server_address"), :Value)

        selected_address = NtpClient.selected_record["address"].to_s

        # disabled in case of PoolNTPorg feature
        # and in case of missing server value
        if selected_address.empty?
          # deleting the current record if current server address is empty
          # and there is some current server record
          if ServerAddressIsInConfiguration()
            NtpClient.selected_record = nil
            NtpClient.storeSyncRecord
          end
        end
        if Convert.to_boolean(UI.QueryWidget(Id("server_address"), :Enabled)) &&
            !selected_address.empty?
          # Save the server_address only when changed
          # do not re-add it (with defaut values) - bug 177575
          if @selected_record_during_init["address"].to_s == selected_address
            log.info "The currently selected server is the same as when starting the module..."
          else
            NtpClient.selected_record["type"] = "server"
            log.info("Storing the current address record: #{NtpClient.selected_record}")
            NtpClient.storeSyncRecord
          end
        end

        log.info("Switching to advanced configuration...")
        return :complex
      end
      ntpEnabledOrDisabled(key, event)
      nil
    end

    # Handle function of the widget
    # @param [String] key string widget id
    # @param [Hash] event map event that caused storing process
    # @return [Symbol] always `complex
    def fudgeButtonHandle(_key, _event)
      :fudge
    end

    def secureInit(_id)
      Builtins.y2milestone("Restrict %1", NtpClient.restrict_map)
      if NtpClient.PolicyIsNonstatic
        UI.ChangeWidget(Id("secure"), :Enabled, false)
      else
        UI.ChangeWidget(Id("secure"), :Value, NtpClient.restrict_map != {})
      end

      nil
    end

    def secureStore(id, _event)
      restrict = Convert.to_boolean(UI.QueryWidget(Id(id), :Value))

      if restrict
        servers = NtpClient.GetUsedNtpServers

        if NtpClient.restrict_map == {}
          Ops.set(
            NtpClient.restrict_map,
            "default",
            "mask" => "", "comment" => "", "options" => "ignore"
          )

          Ops.set(
            NtpClient.restrict_map,
            "127.0.0.1",
            "mask" => "", "comment" => "", "options" => ""
          )

          Builtins.foreach(servers) do |s|
            Ops.set(
              NtpClient.restrict_map,
              s,
              "mask"    => "",
              "comment" => "",
              "options" => "nomodify notrap noquery"
            )
          end
        end
      else
        NtpClient.restrict_map = {}
      end

      nil
    end

    # Initialize the widget
    # @param [String] id any widget id
    def PolicyInit(_id)
      if NtpClient.PolicyIsNomodify
        UI.ChangeWidget(Id("policy_combo"), :Value, Id(:nomodify))
        UI.ChangeWidget(Id("custom_policy"), :Value, "")
        UI.ChangeWidget(Id("custom_policy"), :Enabled, false)
      elsif NtpClient.PolicyIsAuto
        UI.ChangeWidget(Id("policy_combo"), :Value, Id(:auto))
        UI.ChangeWidget(Id("custom_policy"), :Value, "")
        UI.ChangeWidget(Id("custom_policy"), :Enabled, false)
      else
        UI.ChangeWidget(Id("policy_combo"), :Value, Id(:custom))
        UI.ChangeWidget(Id("custom_policy"), :Value, NtpClient.ntp_policy)
        UI.ChangeWidget(Id("custom_policy"), :Enabled, true)
      end

      nil
    end

    # Store settings of the widget
    # @param [String] id any widget id
    # @param [Hash] event map event that caused storing process
    def PolicyStore(_id, _event)
      tmp = NtpClient.ntp_policy
      if UI.QueryWidget(Id("policy_combo"), :Value) == :nomodify
        NtpClient.ntp_policy = ""
      elsif UI.QueryWidget(Id("policy_combo"), :Value) == :auto
        NtpClient.ntp_policy = "auto"
      else
        NtpClient.ntp_policy = Convert.to_string(
          UI.QueryWidget(Id("custom_policy"), :Value)
        )
      end
      if tmp != NtpClient.ntp_policy
        Builtins.y2milestone("set modified to true 3")
        NtpClient.modified = true
      end

      nil
    end

    def RandomServersInit(id)
      ntpEnabledOrDisabled(id, {})
      return nil if id != "use_random_servers"
      Builtins.y2milestone("Initializing random servers")

      rnd_servers = NtpClient.IsRandomServersServiceEnabled
      if rnd_servers
        # Random servers function is enabled
        UI.ChangeWidget(Id("use_random_servers"), :Value, true)
        UI.ChangeWidget(Id("server_address"), :Enabled, false)
        UI.ChangeWidget(Id(:select_server), :Enabled, false)
        UI.ChangeWidget(Id("server_address"), :Value, "")
      else
        # Random servers function is disabled
        UI.ChangeWidget(Id("use_random_servers"), :Value, false)
        if NtpClient.run_service || NtpClient.synchronize_time
          UI.ChangeWidget(Id("server_address"), :Enabled, true)
          UI.ChangeWidget(Id(:select_server), :Enabled, true)
        else
          UI.ChangeWidget(Id("server_address"), :Enabled, false)
          UI.ChangeWidget(Id(:select_server), :Enabled, false)
        end
      end

      nil
    end

    def RandomServersStore(id, _event)
      return nil if id != "use_random_servers"

      if Convert.to_boolean(UI.QueryWidget(Id("use_random_servers"), :Value))
        NtpClient.ActivateRandomPoolServersFunction
      else
        NtpClient.DeActivateRandomPoolServersFunction
      end

      nil
    end

    # Function handles the "use_random_servers" checkbox
    def RandomServersHandle(id, event)
      event = deep_copy(event)
      ntpEnabledOrDisabled(id, event)
      # do not handle anything when called by pressing the checkbox
      return nil if id != "use_random_servers"
      return nil if Ops.get_string(event, "EventReason", "") != "ValueChanged"
      if Ops.get_string(event, "WidgetID", "") != "use_random_servers"
        return nil
      end

      Builtins.y2milestone("Handling random_servers")
      use_random_servers = Convert.to_boolean(
        UI.QueryWidget(Id("use_random_servers"), :Value)
      )
      # If random servers are selected, user is not allowed to enter his/her own NTP server
      if use_random_servers
        Builtins.y2milestone("Activating random servers")
        @ntp_server_before_random_servers = Convert.to_string(
          UI.QueryWidget(Id("server_address"), :Value)
        )
        # if there is already some server defined
        if @ntp_server_before_random_servers != ""
          if !Popup.ContinueCancel(
            _(
              "Enabling Random Servers from pool.ntp.org would\n" \
              "replace the current NTP server.\n\n"               \
              "Really replace the current NTP server?"
            )
          )
            # user has cancelled the operation, return it back
            UI.ChangeWidget(Id("use_random_servers"), :Value, false)
            return nil
          end
        end

        UI.ChangeWidget(Id("server_address"), :Enabled, false)
        UI.ChangeWidget(Id(:select_server), :Enabled, false)
        UI.ChangeWidget(Id("server_address"), :Value, "")
      else
        Builtins.y2milestone("Deactivating random servers")
        UI.ChangeWidget(Id("server_address"), :Enabled, true)
        UI.ChangeWidget(Id(:select_server), :Enabled, true)
        UI.ChangeWidget(
          Id("server_address"),
          :Value,
          @ntp_server_before_random_servers
        )
      end

      nil
    end

    # Redraw the overview table
    def overviewRedraw
      types = {
        # table cell, NTP relationship type
        "server"          => _("Server"),
        # table cell, NTP relationship type
        "peer"            => _("Peer"),
        # table cell, NTP relationship type
        "broadcast"       => _(
          "Outgoing Broadcast"
        ),
        # table cell, NTP relationship type
        "broadcastclient" => _(
          "Incoming Broadcast"
        )
      }
      items = Builtins.maplist(NtpClient.getSyncRecords) do |i|
        type = Ops.get_string(i, "type", "")
        address = Ops.get_string(i, "address", "")
        index = Ops.get_integer(i, "index", -1)
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
          next Item(Id(index), clock_name, device)
        end
        Item(Id(index), Ops.get_string(types, type, ""), address)
      end
      UI.ChangeWidget(Id(:overview), :Items, items)
      UI.SetFocus(Id(:overview))

      nil
    end

    # Handle events on the widget
    # @param [String] id any widget id
    # @param [Hash] event map event that caused storing process
    # @return [Object] event to pass to WS or nil
    def overviewHandle(id, event)
      event = deep_copy(event)
      #    ntpEnabledOrDisabled (id, event);
      if Ops.get(event, "ID") == :display_log
        showLogPopup
        return nil
      end
      ev_id = Ops.get(event, "ID")
      if ev_id == "boot" || ev_id == "never" || ev_id == "sync" ||
          ev_id == "policy_combo"
        pol = Convert.to_symbol(UI.QueryWidget(Id("policy_combo"), :Value))

        enabled = UI.QueryWidget(Id("start"), :CurrentButton) != "never"
        #	UI::ChangeWidget (`id (`advanced), `Enabled, enabled);
        enabled &&= pol != :nomodify
        UI.ChangeWidget(Id(:add), :Enabled, enabled)
        UI.ChangeWidget(Id(:edit), :Enabled, enabled)
        UI.ChangeWidget(Id(:delete), :Enabled, enabled)
        UI.ChangeWidget(Id(:overview), :Enabled, enabled)

        if enabled && pol == :custom
          UI.ChangeWidget(Id("custom_policy"), :Enabled, true)
          UI.ChangeWidget(Id("custom_policy"), :Value, NtpClient.ntp_policy)
        else
          UI.ChangeWidget(Id("custom_policy"), :Enabled, false)
          UI.ChangeWidget(Id("custom_policy"), :Value, "")
        end
        Builtins.y2milestone(
          "set modified from %1 to true 4.1 id %2 map %3",
          NtpClient.modified,
          id,
          event
        )
        NtpClient.modified = true
        return nil
      end
      types = {
        "server"          => :server,
        "peer"            => :peer,
        "__clock"         => :clock,
        "broadcast"       => :bcast,
        "broadcastclient" => :bcastclient
      }
      if Ops.get(event, "ID") == :add
        NtpClient.selectSyncRecord(-1)
        @peer_type_selected = nil
        Builtins.y2milestone(
          "set modified from %1 to true 4.2 id %2 map %3",
          NtpClient.modified,
          id,
          event
        )
        NtpClient.modified = true
        return :add
      elsif Ops.get(event, "ID") == :edit || Ops.get(event, "ID") == :overview
        NtpClient.selectSyncRecord(
          Convert.to_integer(UI.QueryWidget(Id(:overview), :CurrentItem))
        )
        type = Ops.get_string(NtpClient.selected_record, "type", "")
        Builtins.y2milestone(
          "set modified from %1 to true 4.3 id %2 map %3",
          NtpClient.modified,
          id,
          event
        )
        NtpClient.modified = true
        return Ops.get(types, type)
      elsif Ops.get(event, "ID") == :delete
        # yes-no popup
        if Confirm.DeleteSelected
          NtpClient.deleteSyncRecord(
            Convert.to_integer(UI.QueryWidget(Id(:overview), :CurrentItem))
          )
          overviewRedraw
          @sync_record_modified = true
          Builtins.y2milestone(
            "set modified from %1 to true 4.4 id %2 map %3",
            NtpClient.modified,
            id,
            event
          )
          NtpClient.modified = true
        end
      end
      nil
    end

    # Initialize the widget
    # @param [String] id any widget id
    def overviewInit(id)
      tmp = NtpClient.modified
      overviewRedraw
      overviewHandle(id, "ID" => "boot")
      NtpClient.modified = tmp

      nil
    end

    # Initialize the widget
    # @param [String] id any widget id
    def addressInit(id)
      # remember selected_record_during_init only when the module is started
      # #230240
      if @selected_record_during_init == {}
        @selected_record_during_init = deep_copy(NtpClient.selected_record)
      end

      ad = NtpClient.ad_controller
      if ad != ""
        UI.ChangeWidget(Id(id), :Value, ad)
      else
        UI.ChangeWidget(
          Id(id),
          :Value,
          Ops.get_string(NtpClient.selected_record, "address", "")
        )
      end
      UI.SetFocus(Id(id))

      nil
    end

    # Store settings of the widget
    # @param [String] id any widget id
    # @param [Hash] event map event that caused storing process
    def addressStore(id, event)
      event = deep_copy(event)
      # Don't store anything in case of switching to the advanced configuration
      return if Ops.get(event, "ID") == :complex

      Ops.set(
        NtpClient.selected_record,
        "address",
        UI.QueryWidget(Id(id), :Value)
      )
      if NtpClient.simple_dialog
        # Save the server_address only when changed
        # do not re-add it (with defaut values) - bug 177575
        if Ops.get_string(@selected_record_during_init, "address", "") ==
            Ops.get_string(NtpClient.selected_record, "address", "")
          Builtins.y2milestone(
            "The currently selected server is the same as when starting the module..."
          )
        else
          Builtins.y2milestone(
            "Storing the server address in simple configuration"
          )
          Ops.set(NtpClient.selected_record, "type", "server")
        end
      end

      nil
    end

    # Handle events on the widget
    # @param [String] id string widget id
    # @param [Hash] event map event that caused storing process
    # @return [Boolean] is successful
    def serverAddressValidate(_id, event)
      event = deep_copy(event)
      # NTP Client is disabled, do not check the server name
      if Ops.get(event, "ID") == :next && UI.WidgetExists(Id("start")) &&
          Convert.to_string(UI.QueryWidget(Id("start"), :CurrentButton)) == "never"
        return true
      end
      # do not check the server IP/Host when changing dialog to "Select"
      #   or when switching to the advanced configuration
      if Ops.get(event, "ID") == :select_local ||
          Ops.get(event, "ID") == :select_public ||
          Ops.get(event, "ID") == :complex
        return true
      end

      CheckCurrentSimpleConfiguration(true)
    end

    # Handle events on the widget
    # @param [String] id string widget id
    # @param [Hash] event map event that caused storing process
    # @return [Symbol] event to pass to WS or nil
    def serverAddressHandle(id, event)
      event = deep_copy(event)
      ev_id = Ops.get(event, "ID")
      server = Convert.to_string(UI.QueryWidget(Id(id), :Value))
      if ev_id == "boot" || ev_id == "never"
        enabled = UI.QueryWidget(Id("start"), :CurrentButton) != "never"
        # checkbox selected - random servers feature
        if UI.QueryWidget(Id("use_random_servers"), :Value) == true
          UI.ChangeWidget(Id(id), :Enabled, false)
          UI.ChangeWidget(Id(:select_server), :Enabled, false)
        else
          UI.ChangeWidget(Id(id), :Enabled, enabled)
          UI.ChangeWidget(Id(:select_server), :Enabled, enabled)
        end
        UI.ChangeWidget(Id(:test_server), :Enabled, enabled)

        return nil
      end
      if ev_id == :test_server
        if UI.WidgetExists(Id("use_random_servers")) &&
            Convert.to_boolean(UI.QueryWidget(Id("use_random_servers"), :Value))
          NtpClient.TestNtpServer(
            Ops.get(
              NtpClient.random_pool_servers,
              Builtins.random(4),
              "0.pool.ntp.org"
            ),
            :result_popup
          )
        elsif serverAddressValidate("server_address", {})
          NtpClient.TestNtpServer(server, :result_popup)
        end
      elsif ev_id == :select_local
        return :select_local
      elsif ev_id == :select_public
        return :select_public
      end

      nil
    end

    # Initialize the widget
    # @param [String] id any widget id
    def optionsInit(_id)
      # bnc#438704, add a recommended option
      UI.ChangeWidget(
        Id("options"),
        :Value,
        Ops.get_string(NtpClient.selected_record, "options", "iburst")
      )

      nil
    end

    # Store settings of the widget
    # @param [String] id any widget id
    # @param [Hash] event map event that caused storing process
    def optionsStore(_id, _event)
      Ops.set(
        NtpClient.selected_record,
        "options",
        UI.QueryWidget(Id("options"), :Value)
      )

      nil
    end

    def restrictOptionsInit(_id)
      address = Ops.get_string(NtpClient.selected_record, "address", "")
      if NtpClient.restrict_map == {} || NtpClient.PolicyIsNonstatic
        UI.ChangeWidget(Id("ac_options"), :Enabled, false)
      elsif Builtins.haskey(NtpClient.restrict_map, address)
        UI.ChangeWidget(
          Id("ac_options"),
          :Value,
          Ops.get_string(NtpClient.restrict_map, [address, "options"], "")
        )
      else
        UI.ChangeWidget(Id("ac_options"), :Value, "notrap nomodify noquery")
      end

      nil
    end

    def restrictOptionsStore(_id, _event)
      address = Ops.get_string(NtpClient.selected_record, "address", "")
      opts = Convert.to_string(UI.QueryWidget(Id("ac_options"), :Value))

      return if address == ""
      if NtpClient.PolicyIsNonstatic
        NtpClient.restrict_map = {}
        return
      end
      if Builtins.haskey(NtpClient.restrict_map, address)
        Ops.set(NtpClient.restrict_map, [address, "options"], opts)
      else
        Ops.set(
          NtpClient.restrict_map,
          address,
          "comment" => "", "mask" => "", "options" => opts
        )
      end

      nil
    end

    # Initialize the widget
    # @param [String] id any widget id
    def peerTypesInit(_id)
      if @peer_type_selected
        UI.ChangeWidget(Id("peer_types"), :CurrentButton, @peer_type_selected)
      else
        UI.ChangeWidget(Id("peer_types"), :CurrentButton, "server")
      end

      nil
    end

    # Handle events on the widget
    # @param [String] id any widget id
    # @param [Hash] event map event that caused storing process
    # @return [Symbol] event to pass to WS or nil
    def peerTypesHandle(_id, event)
      event = deep_copy(event)
      @peer_type_selected = Convert.to_string(
        UI.QueryWidget(Id("peer_types"), :CurrentButton)
      )
      types = {
        "server"          => :server,
        "peer"            => :peer,
        "__clock"         => :clock,
        "broadcast"       => :bcast,
        "broadcastclient" => :bcastclient
      }
      if Ops.get(event, "ID") == :next
        Ops.set(NtpClient.selected_record, "type", @peer_type_selected)
        return Ops.get(types, @peer_type_selected)
      end
      nil
    end

    # Initialize the widget
    # @param [String] id string widget id
    def createSymlinkInit(id)
      UI.ChangeWidget(
        Id(id),
        :Value,
        Ops.get_boolean(NtpClient.selected_record, "create_symlink", false)
      )

      nil
    end

    # Handle function of the widget
    # @param [String] id string widget id
    # @param [Hash] event map event that caused storing process
    # @return [Symbol] always nil
    def createSymlinkHandle(id, _event)
      active = Convert.to_boolean(UI.QueryWidget(Id("create_symlink"), :Value))
      if id == "clock_type"
        current = Builtins.tointeger(
          Convert.to_string(UI.QueryWidget(Id(id), :Value))
        )
        active &&= Ops.get(@clock_types, [current, "device"], "") == ""
      end
      UI.ChangeWidget(Id("device"), :Enabled, active)
      UI.ChangeWidget(Id("browse"), :Enabled, active)
      nil
    end

    # Store settings of the widget
    # @param [String] id string widget id
    # @param [Hash] event map event that caused storing process
    def createSymlinkStore(id, _event)
      Ops.set(
        NtpClient.selected_record,
        "create_symlink",
        Convert.to_boolean(UI.QueryWidget(Id(id), :Value))
      )

      nil
    end

    # Handle function of the widget
    # @param [String] id string widget id
    # @param [Hash] event map event that caused storing process
    # @return [Symbol] always nil
    def clockTypeHandle(id, event)
      event = deep_copy(event)
      current = Builtins.tointeger(
        Convert.to_string(UI.QueryWidget(Id(id), :Value))
      )
      hw_avail = Ops.get(@clock_types, [current, "device"], "") != ""
      UI.ChangeWidget(Id("create_symlink"), :Enabled, hw_avail)
      createSymlinkHandle(id, event)
    end

    # Initialize the widget
    # @param [String] id string widget id
    def clockTypeInit(id)
      UI.ChangeWidget(
        Id(id),
        :Value,
        Builtins.sformat(
          "%1",
          getClockType(Ops.get_string(NtpClient.selected_record, "address", ""))
        )
      )
      clockTypeHandle(id, {})

      nil
    end

    # Store settings of the widget
    # @param [String] id string widget id
    # @param [Hash] event map event that caused storing process
    def clockTypeStore(id, _event)
      Ops.set(
        NtpClient.selected_record,
        "address",
        setClockType(
          Ops.get_string(NtpClient.selected_record, "address", ""),
          Builtins.tointeger(Convert.to_string(UI.QueryWidget(Id(id), :Value)))
        )
      )

      nil
    end

    # Initialize the widget
    # @param [String] id string widget id
    def unitNumberInit(id)
      UI.ChangeWidget(
        Id(id),
        :Value,
        getClockUnitNumber(
          Ops.get_string(NtpClient.selected_record, "address", "")
        )
      )

      nil
    end

    # Store settings of the widget
    # @param [String] id string widget id
    # @param [Hash] event map event that caused storing process
    def unitNumberStore(id, _event)
      Ops.set(
        NtpClient.selected_record,
        "address",
        setClockUnitNumber(
          Ops.get_string(NtpClient.selected_record, "address", ""),
          Convert.to_integer(UI.QueryWidget(Id(id), :Value))
        )
      )

      nil
    end

    # Handle function of the widget
    # @param [String] id string widget id
    # @param [Hash] event map event that caused storing process
    # @return [Symbol] always nil
    def browseButtonHandle(_id, _event)
      current = Convert.to_string(UI.QueryWidget(Id("device"), :Value))
      current = "/dev" if current == ""
      # popup header
      current = UI.AskForExistingFile(current, "", _("Select the Device"))
      UI.ChangeWidget(Id("device"), :Value, current) unless current.nil?
      nil
    end

    # Initialize the widget
    # @param [String] id string widget id
    def deviceInit(id)
      UI.ChangeWidget(
        Id(id),
        :Value,
        Ops.get_string(NtpClient.selected_record, "device", "")
      )

      nil
    end

    # Store settings of the widget
    # @param [String] id string widget id
    # @param [Hash] event map event that caused storing process
    def deviceStore(id, _event)
      Ops.set(
        NtpClient.selected_record,
        "device",
        Convert.to_string(UI.QueryWidget(Id(id), :Value))
      )

      nil
    end

    # Handle function of the widget
    # @param [String] id string widget id
    # @param [Hash] event map event that caused storing process
    # @return [Symbol] always nil
    def ServerListHandle(_id, event)
      event = deep_copy(event)
      #    if (event["ID"]:nil == "list_rb" || event["ID"]:nil == "lookup_rb")
      #    {
      #	boolean enabled = (boolean)UI::QueryWidget (`id ("list_rb"), `Value);
      #	UI::ChangeWidget (`id (`country), `Enabled, enabled);
      #	UI::ChangeWidget (`id (`servers), `Enabled, enabled);
      #	return nil;
      #    }
      country = Convert.to_string(UI.QueryWidget(Id(:country), :Value))
      country = "" if country.nil?
      Builtins.y2milestone(
        "Handling server list change, last country: %1, current country: %2",
        @last_country,
        country
      )
      if country != @last_country
        @last_country = country

        items = NtpClient.GetNtpServersByCountry(country, false)
        UI.ReplaceWidget(
          :servers_rp,
          VBox(
            # Combobox has at least 40 characters
            # bug #97184
            HSpacing(40),
            ComboBox(
              Id(:servers),
              Opt(:hstretch),
              # selection box header
              _("Public NTP &Servers"),
              items
            )
          )
        )
        return nil
      end
      if Ops.get(event, "ID") == :test || Ops.get(event, "ID") == :info
        server = Convert.to_string(UI.QueryWidget(Id(:servers), :Value))
        if server.nil? || server == ""
          # message report (no server selected)
          Report.Message(_("Select an NTP server."))
          return nil
        end
        if Ops.get(event, "ID") == :test
          NtpClient.TestNtpServer(server, :result_popup)
        end
        return nil
      end
      nil
    end

    # Initialize the widget
    # @param [String] id string widget id
    def ServerListInit(id)
      country_names = NtpClient.GetCountryNames
      country_codes = Builtins.mapmap(country_names) { |k, v| { v => k } }
      countries_lst = Builtins.toset(Builtins.maplist(NtpClient.GetNtpServers) do |_s, m|
        country = Ops.get(m, "country", "")
        label = Ops.get(country_names, country, country)
        label
      end)
      countries_lst = Builtins.lsort(countries_lst)
      countries = Builtins.maplist(countries_lst) do |label|
        code = Ops.get(country_codes, label, label)
        Item(Id(code), label)
      end
      # combo box item
      countries = Builtins.prepend(countries, Item(Id(""), _("All Countries")))
      UI.ReplaceWidget(
        :country_rp,
        ComboBox(
          Id(:country),
          Opt(:notify, :hstretch),
          # combo box header
          _("&Country"),
          countries
        )
      )
      @last_country = nil

      lang = NtpClient.GetCurrentLanguageCode
      if lang
        Builtins.y2milestone("Current language: %1", lang)
        UI.ChangeWidget(Id(:country), :Value, lang)
      end
      ServerListHandle(id, {})
      ServerListHandle(id, "ID" => "list_rb")

      nil
    end

    # Store settings of the widget
    # @param [String] id string widget id
    # @param [Hash] event map event that caused storing process
    def ServerListStore(_id, _event)
      if UI.WidgetExists(Id("list_rb")) &&
          !Convert.to_boolean(UI.QueryWidget(Id("list_rb"), :Value))
        return
      end
      address = Convert.to_string(UI.QueryWidget(Id(:servers), :Value))
      Ops.set(NtpClient.selected_record, "address", address)
      # Do not forget to add type of the record - here we have 'server' (#216456)
      Ops.set(NtpClient.selected_record, "type", "server")

      nil
    end

    # Validation function of a widget
    # @param [String] id string widget id
    # @param [Hash] event map event that caused validation
    # @return [Boolean] true if validation succeeded
    def ServerListValidate(_id, _event)
      if UI.WidgetExists(Id("list_rb")) &&
          !Convert.to_boolean(UI.QueryWidget(Id("list_rb"), :Value))
        return true
      end
      address = Convert.to_string(UI.QueryWidget(Id(:servers), :Value))
      if address == "" || address.nil?
        # report message
        Report.Message(_("Select an NTP server."))
        return false
      end
      true
    end

    # Initialize the widget
    # @param [String] id string widget id
    def ServersSourceInit(id)
      UI.ChangeWidget(Id(id), :CurrentButton, "lookup_rb")

      nil
    end

    def FoundServersHandle(_id, event)
      event = deep_copy(event)
      #    if (event["ID"]:nil == "list_rb" || event["ID"]:nil == "lookup_rb")
      #    {
      #	boolean enabled = (boolean)UI::QueryWidget (`id ("lookup_rb"), `Value);
      #	UI::ChangeWidget (`id ("server_address"), `Enabled, enabled);
      #	UI::ChangeWidget (`id (`lookup_server), `Enabled, enabled);
      #	return nil;
      #    }
      if Ops.get(event, "ID") == :lookup_server
        # TRANSLATORS: Busy message
        UI.OpenDialog(Label(_("Scanning for NTP servers on your network...")))

        method = :slp
        server_names = Builtins.sort(NtpClient.DetectNtpServers(method))
        @found_servers_cache = deep_copy(server_names)

        UI.CloseDialog

        # no server has been found
        if server_names == [] || server_names.nil?
          # firewall probably blocks broadcast reply
          if SuSEFirewall.GetStartService
            # TRANSLATORS: Popup error - no NTP server has been found during scanning the network.
            #              There is a very high possibility that is is because of running firewall.
            Report.Error(
              _(
                "No NTP server has been found on your network.\n"    \
                "This could be caused by a running SuSEfirewall2,\n" \
                "which probably blocks the network scanning."
              )
            )
            # no server is available on the network
          else
            # TRANSLATORS: Popup error - no NTP server has been found during scanning the network.
            Report.Error(_("No NTP server has been found on your network."))
          end
          return nil
        end

        UI.ReplaceWidget(
          :server_address_rp,
          ComboBox(
            Id("server_address"),
            Opt(:editable, :hstretch),
            # combo box label
            _("Address"),
            server_names
          )
        )
        return nil
      end
      nil
    end

    # Initialize the widget
    # @param [String] id string widget id
    def FoundServersInit(id)
      items = []

      # fate#302863: suggest ntp.$domain
      if @found_servers_cache.nil?
        guessed = Ops.add("ntp.", Hostname.CurrentDomain)
        @found_servers_cache = if NtpClient.TestNtpServer(guessed, :transient_popup)
          [guessed]
        else
          []
        end
      end

      Builtins.foreach(@found_servers_cache) do |server|
        items = Builtins.add(items, Item(Id(server), server))
      end
      UI.ChangeWidget(Id("server_address"), :Items, items)
      FoundServersHandle(id, "ID" => "list_rb")

      nil
    end

    # Store settings of the widget
    # @param [String] id string widget id
    # @param [Hash] event map event that caused storing process
    def FoundServersStore(_id, _event)
      #    if (UI::WidgetExists (`id ("lookup_rb"))
      #    	&& ! (boolean)UI::QueryWidget (`id ("lookup_rb"), `Value))
      #    {
      #    	return;
      #    }
      address = Convert.to_string(UI.QueryWidget(Id("server_address"), :Value))
      Ops.set(NtpClient.selected_record, "address", address)

      nil
    end

    def FoundServersValidate(_id, _event)
      #    if (UI::WidgetExists (`id ("lookup_rb"))
      #	&& ! (boolean)UI::QueryWidget (`id ("lookup_rb"), `Value))
      #    {
      #	return true;
      #    }
      server = Convert.to_string(UI.QueryWidget(Id("server_address"), :Value))
      if server.nil? || server == ""
        UI.SetFocus(Id("server_address"))
        # popup message
        Popup.Message(_("No server is selected."))
        return false
      end
      true
    end

    def LocalSelectTestHandle(_id, _event)
      #    if ((boolean)UI::QueryWidget (`id ("lookup_rb"), `Value))
      #    {
      server = Convert.to_string(UI.QueryWidget(Id("server_address"), :Value))
      #    }
      #    else
      #    {
      #	server = (string)UI::QueryWidget (`id (`servers), `Value);
      #    }
      NtpClient.TestNtpServer(server, :result_popup)
      nil
    end

    def PublicSelectTestHandle(_id, _event)
      #    if ((boolean)UI::QueryWidget (`id ("lookup_rb"), `Value))
      #    {
      #	server = (string)UI::QueryWidget (`id ("server_address"), `Value);
      #    }
      #    else
      #    {
      server = Convert.to_string(UI.QueryWidget(Id(:servers), :Value))
      #    }
      NtpClient.TestNtpServer(server, :result_popup)
      nil
    end

    # Initialize all widgets
    # @return a map of widgets
    def InitWidgets
      address = {
        "widget" => :textentry,
        # text entry label
        "label"  => _("A&ddress"),
        "init"   => fun_ref(method(:addressInit), "void (string)"),
        "store"  => fun_ref(method(:addressStore), "void (string, map)")
      }

      {
        "complex_button"     => {
          "widget"        => :push_button,
          # push button label
          "label"         => _("Ad&vanced Configuration"),
          "help"          => Ops.get_string(@HELPS, "complex_button", ""),
          "handle_events" => ["complex_button", "never", "boot"],
          "handle"        => fun_ref(
            method(:complexButtonHandle),
            "symbol (string, map)"
          )
        },
        "fudge_button"       => {
          "widget"        => :push_button,
          # push button label
          "label"         => _("&Driver Calibration"),
          "help"          => Ops.get_string(@HELPS, "fudge_button", ""),
          "handle_events" => ["fudge_button"],
          "handle"        => fun_ref(
            method(:fudgeButtonHandle),
            "symbol (string, map)"
          )
        },
        "interval"           => {
          "widget"  => :intfield,
          "label"   => _("&Interval of the Synchronization in Minutes"),
          "minimum" => 1,
          "maximum" => 60,
          "init"    => fun_ref(method(:intervalInit), "void (string)"),
          "store"   => fun_ref(method(:intervalStore), "void (string, map)"),
          "no_help" => true,
          "handle"  => fun_ref(method(:timeSyncOrNo), "symbol (string, map)")
        },
        "start"              => {
          "widget"        => :radio_buttons,
          # frame
          "label"         => _("Start NTP Daemon"),
          "items"         => [
            # radio button
            ["never", _("Only &Manually")],
            # radio button
            ["sync", _("&Synchronize without Daemon")],
            # radio button
            ["boot", _("Now and on &Boot")]
          ],
          "help"          => Ops.get_string(@HELPS, "start", ""),
          "init"          => fun_ref(method(:startInit), "void (string)"),
          "store"         => fun_ref(method(:startStore), "void (string, map)"),
          "handle"        => fun_ref(
            method(:startHandle),
            "symbol (string, map)"
          ),
          "handle_events" => ["boot", "never", "sync"],
          "opt"           => [:notify]
        },
        "secure"             => {
          "widget" => :checkbox,
          # TRANSLATORS:
          "label"  => _(
            "&Restrict NTP Service to Configured Servers Only "
          ),
          "init"   => fun_ref(method(:secureInit), "void (string)"),
          "store"  => fun_ref(method(:secureStore), "void (string, map)"),
          "help"   => Ops.get_string(@HELPS, "secure", "")
        },
        "policy_combo"       => { # FIXME
          "widget" => :combobox,
          "opt"    => [:notify],
          "items"  => [
            # combo box item FIXME usability
            [:nomodify, _("Manual")],
            # combo box item
            [:auto, _("Auto")],
            # combo box item
            [:custom, _("Custom")]
          ],
          "label"  => _("&Runtime Configuration Policy"),
          "init"   => fun_ref(method(:PolicyInit), "void (string)"),
          "store"  => fun_ref(method(:PolicyStore), "void (string, map)"),
          "handle" => fun_ref(method(:ntpEnabledOrDisabled), "symbol (string, map)"),
          "help"   => Ops.get_string(@HELPS, "policy_combo", "")
        },
        "custom_policy"      => { # FIXME
          "widget" => :textentry,
          "label"  => _("&Custom Policy"),
          "handle" => fun_ref(method(:ntpEnabledOrDisabled), "symbol (string, map)"),
          "help"   => Ops.get_string(@HELPS, "custom_policy", "")
        },
        "use_random_servers" => {
          "widget" => :checkbox,
          "opt"    => [:notify],
          # check box
          "label"  => _("&Use Random Servers from pool.ntp.org"),
          "init"   => fun_ref(method(:RandomServersInit), "void (string)"),
          "store"  => fun_ref(method(:RandomServersStore), "void (string, map)"),
          "handle" => fun_ref(method(:RandomServersHandle), "symbol (string, map)"),
          "help"   => Ops.get_string(@HELPS, "use_random_servers", "")
        },
        "server_address"     => Builtins.union(
          address,
          # text entry label
          "label"             => _("&Address"),
          "help"              => Ops.get_string(@HELPS, "server_address", ""),
          "handle"            => fun_ref(
            method(:serverAddressHandle),
            "symbol (string, map)"
          ),
          "validate_type"     => :function,
          "validate_function" => fun_ref(
            method(:serverAddressValidate),
            "boolean (string, map)"
          ),
          "widget"            => :custom,
          "custom_widget"     => VBox(
            HBox(
              TextEntry(
                Id("server_address"),
                Opt(:hstretch),
                # text entry
                _("&Address")
              ),
              VBox(
                Label(" "),
                # push button
                MenuButton(
                  Id(:select_server),
                  _("&Select..."),
                  [
                    Item(Id(:select_local), _("Local NTP Server")),
                    Item(Id(:select_public), _("Public NTP Server"))
                  ]
                )
              )
            ),
            HBox(
              HStretch(),
              # push button
              PushButton(Id(:test_server), _("&Test")),
              HStretch()
            )
          )
        ),
        "overview"           => {
          "widget"        => :custom,
          "custom_widget" => VBox(
            Table(
              Id(:overview),
              Opt(:notify),
              Header(
                # table header
                _("Synchronization Type"),
                # table header
                _("Address")
              )
            ),
            HBox(
              PushButton(Id(:add), Label.AddButton), # menu button
              #		    `MenuButton (`id (`advanced), _("&Advanced..."), [
              # item of menu button
              #			`item (`id (`display_log), _("Display &Log...")),
              #		    ])
              PushButton(Id(:edit), Label.EditButton),
              PushButton(Id(:delete), Label.DeleteButton),
              HStretch(),
              # push button
              PushButton(Id(:display_log), _("Display &Log..."))
            )
          ),
          "help"          => Ops.get_string(@HELPS, "overview", ""),
          "init"          => fun_ref(method(:overviewInit), "void (string)"),
          "handle"        => fun_ref(
            method(:overviewHandle),
            "symbol (string, map)"
          )
        },
        "paddress"           => Builtins.union(
          address,
          "help" => Ops.get_string(@HELPS, "paddress", "")
        ),
        "bcaddress"          => Builtins.union(
          address,
          "help" => Ops.get_string(@HELPS, "bcaddress", "")
        ),
        "bccaddress"         => Builtins.union(
          address,
          "help" => Ops.get_string(@HELPS, "bccaddress", "")
        ),
        "clock_type"         => {
          "widget" => :combobox,
          # combo box label
          "label"  => _("Clock &Type"),
          "items"  => getClockTypesCombo,
          "help"   => Ops.get_string(@HELPS, "clock_type", ""),
          "opt"    => [:notify],
          "init"   => fun_ref(method(:clockTypeInit), "void (string)"),
          "handle" => fun_ref(method(:clockTypeHandle), "symbol (string, map)"),
          "store"  => fun_ref(method(:clockTypeStore), "void (string, map)")
        },
        "unit_number"        => {
          "widget"  => :intfield,
          # int field
          "label"   => _("Unit &Number"),
          "help"    => Ops.get_string(@HELPS, "unit_number", ""),
          "minimum" => 0,
          "maximum" => 3,
          "init"    => fun_ref(method(:unitNumberInit), "void (string)"),
          "store"   => fun_ref(method(:unitNumberStore), "void (string, map)")
        },
        "create_symlink"     => {
          "widget"        => :checkbox,
          # check box
          "label"         => _("Create &Symlink"),
          "opt"           => [:notify],
          "handle_events" => ["create_symlink"],
          "init"          => fun_ref(
            method(:createSymlinkInit),
            "void (string)"
          ),
          "handle"        => fun_ref(
            method(:createSymlinkHandle),
            "symbol (string, map)"
          ),
          "store"         => fun_ref(
            method(:createSymlinkStore),
            "void (string, map)"
          ),
          "no_help"       => true
        },
        "device"             => {
          "widget" => :textentry,
          # text entry
          "label"  => _("&Device"),
          "init"   => fun_ref(method(:deviceInit), "void (string)"),
          "store"  => fun_ref(method(:deviceStore), "void (string, map)"),
          "help"   => Ops.get_string(@HELPS, "device", "")
        },
        "browse"             => {
          "widget"        => :push_button,
          "label"         => Label.BrowseButton,
          "handle_events" => ["browse"],
          "handle"        => fun_ref(
            method(:browseButtonHandle),
            "symbol (string, map)"
          ),
          "no_help"       => true
        },
        "options"            => {
          "widget" => :textentry,
          # text entry label
          "label"  => Label.Options,
          "init"   => fun_ref(method(:optionsInit), "void (string)"),
          "store"  => fun_ref(method(:optionsStore), "void (string, map)"),
          "help"   => Ops.get_string(@HELPS, "options", "")
        },
        "ac_options"         => {
          "widget" => :textentry,
          "label"  => _("Access Control Options"),
          "init"   => fun_ref(method(:restrictOptionsInit), "void (string)"),
          "store"  => fun_ref(
            method(:restrictOptionsStore),
            "void (string, map)"
          ),
          "help"   => Ops.get_string(@HELPS, "restrict", "")
        },
        "peer_types"         => {
          "widget"   => :radio_buttons,
          "items"    => [
            # radio button, NTP relationship type
            ["server", _("&Server")],
            # radio button, NTP relationship type
            ["peer", _("&Peer")],
            # radio button, NTP relationship type
            ["__clock", _("&Radio Clock")],
            # radio button, NTP relationship type
            ["broadcast", _("&Outgoing Broadcast")],
            # radio button, NTP relationship type
            ["broadcastclient", _("&Incoming Broadcast")]
          ],
          # frame
          "label"    => _("Type"),
          "init"     => fun_ref(method(:peerTypesInit), "void (string)"),
          "handle"   => fun_ref(
            method(:peerTypesHandle),
            "symbol (string, map)"
          ),
          "help"     => Ops.get_string(@HELPS, "peer_types", ""),
          "hspacing" => 3,
          "vspacing" => 1
        },
        "servers_source"     => {
          "widget" => :radio_buttons,
          "items"  => [
            # radio button
            ["lookup_rb", _("Loc&al Network")],
            # radio button
            ["list_rb", _("&Public NTP Server")]
          ],
          "opt"    => [:notify],
          "init"   => fun_ref(method(:ServersSourceInit), "void (string)"),
          # frame label
          "label"  => _("NTP Server Location"),
          "help"   => Ops.get_string(@HELPS, "servers_source", "")
        },
        "found_servers"      => {
          "widget"            => :custom,
          "custom_widget"     => HBox(
            HWeight(
              3,
              ReplacePoint(
                Id(:server_address_rp),
                ComboBox(
                  Id("server_address"),
                  Opt(:editable, :hstretch),
                  # combo box label
                  _("&Address"),
                  []
                )
              )
            ),
            HWeight(
              1,
              VBox(
                Label(" "),
                # push button
                PushButton(Id(:lookup_server), _("&Lookup"))
              )
            )
          ),
          "init"              => fun_ref(
            method(:FoundServersInit),
            "void (string)"
          ),
          "handle"            => fun_ref(
            method(:FoundServersHandle),
            "symbol (string, map)"
          ),
          "store"             => fun_ref(
            method(:FoundServersStore),
            "void (string, map)"
          ),
          "validate_type"     => :function,
          "validate_function" => fun_ref(
            method(:FoundServersValidate),
            "boolean (string, map)"
          ),
          "help"              => Ops.get_string(@HELPS, "found_servers", "")
        },
        "servers_list"       => {
          "widget"            => :custom,
          "custom_widget"     => VBox(
            ReplacePoint(
              Id(:country_rp),
              ComboBox(
                Id(:country),
                Opt(:notify, :hstretch),
                # combo box header
                _("&Country"),
                []
              )
            ),
            ReplacePoint(
              Id(:servers_rp),
              ComboBox(
                Id(:servers),
                Opt(:hstretch),
                # selection box header
                _("Public NTP &Servers"),
                []
              )
            )
          ),
          "init"              => fun_ref(
            method(:ServerListInit),
            "void (string)"
          ),
          "handle"            => fun_ref(
            method(:ServerListHandle),
            "symbol (string, map)"
          ),
          "store"             => fun_ref(
            method(:ServerListStore),
            "void (string, map)"
          ),
          "validate_type"     => :function,
          "validate_function" => fun_ref(
            method(:ServerListValidate),
            "boolean (string, map)"
          ),
          "help"              => Ops.get_string(@HELPS, "servers_list", "")
        },
        "select_test_local"  => {
          "widget"        => :push_button,
          # push button
          "label"         => _("&Test"),
          "handle_events" => ["select_test_local"],
          "handle"        => fun_ref(
            method(:LocalSelectTestHandle),
            "symbol (string, map)"
          ),
          "help"          => Ops.get_string(@HELPS, "selected_test", "")
        },
        "select_test_public" => {
          "widget"        => :push_button,
          # push button
          "label"         => _("&Test"),
          "handle_events" => ["select_test_public"],
          "handle"        => fun_ref(
            method(:PublicSelectTestHandle),
            "symbol (string, map)"
          ),
          "help"          => Ops.get_string(@HELPS, "selected_test", "")
        },
        "firewall"           => CWMFirewallInterfaces.CreateOpenFirewallWidget(
          "services"        => NtpClient.firewall_services,
          "display_details" => true
        )
      }
    end
  end
end
