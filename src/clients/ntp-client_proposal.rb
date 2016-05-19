# encoding: utf-8

# File:	clients/ntp-client_proposal.ycp
# Summary:	Installation client for ntp configuration
# Author:	Bubli <kmachalkova@suse.cz>
#
# This is used as the general interface between yast2-country
# (time,timezone) and yast2-ntp-client.
module Yast
  class NtpClientProposalClient < Client
    def main
      Yast.import "UI"
      textdomain "ntp-client"


      Yast.import "Address"
      Yast.import "NetworkService"
      Yast.import "NtpClient"
      Yast.import "Service"
      Yast.import "String"
      Yast.import "Stage"
      Yast.import "PackageSystem"
      Yast.import "Popup"
      Yast.import "Progress"
      Yast.import "Report"
      Yast.import "Timezone"
      Yast.import "Wizard"

      #     API:
      #
      # Usual *_proposal functions: MakeProposal, AskUser, Write.
      # (but not Description; see, it just *looks* like *_proposal)
      # Additionally:
      #  GetNTPEnabled  (queries Service::Enabled)
      #  SetUseNTP [ntp_used]
      @ret = nil
      @func = ""
      @param = {}

      if Ops.greater_than(Builtins.size(WFM.Args), 0) &&
          Ops.is_string?(WFM.Args(0))
        @func = Convert.to_string(WFM.Args(0))
        if Ops.greater_than(Builtins.size(WFM.Args), 1) &&
            Ops.is_map?(WFM.Args(1))
          @param = Convert.to_map(WFM.Args(1))
        end
      end

      Builtins.y2milestone(
        "ntp-client_proposal called func %1 param %2",
        @func,
        @param
      )

      # FIXME must go to module to preserve value
      @ntp_was_used = false



      if false
        return
      elsif @func == "GetNTPEnabled"
        @ret = GetNTPEnabled()
      elsif @func == "SetUseNTP"
        NtpClient.ntp_selected = Ops.get_boolean(@param, "ntp_used", false)
        @ret = true
      elsif @func == "MakeProposal"
        @ret = MakeProposal()
      elsif @func == "Write"
        @ret = Write(@param)
      elsif @func == "ui_help_text"
        @ret = ui_help_text
      elsif @func == "ui_init"
        @rp = Ops.get_term(@param, "replace_point") { Id(:rp) }
        @ft = Ops.get_boolean(@param, "first_time", false)
        @ret = ui_init(@rp,@ft)
      elsif @func == "ui_try_save"
        @ret = ui_try_save
      elsif @func == "ui_enable_disable_widgets"
        @ret = ui_enable_disable_widgets(
          Ops.get_boolean(@param, "enabled", false)
        )
      elsif @func == "ui_handle"
        @ret = ui_handle(Ops.get(@param, "ui"))
      end

      deep_copy(@ret)
    end

    def ui_help_text
      # help text
      tmp = _(
        "<p>Press <b>Synchronize Now</b>, to get your system time set correctly using the selected NTP server. If you want to make use of NTP permanently, enable the <b>Save NTP Configuration</b> option</p>"
      )

      tmp = Ops.add(
        tmp,
        _(
          "<p>Enabling <b>Run NTP as daemon</b> option, the NTP service will be started as daemon. Otherwise the system time will be synchronized periodically. The default interval is 15 min. You can change it after installation with the <b>yast2 ntp-client module</b>.</p>"
        )
      )

      # help text, cont.
      if !Stage.initial
        tmp = Ops.add(
          tmp,
          _(
            "<p>Using the <b>Configure</b> button, open the advanced NTP configuration.</p>"
          )
        )
      end

      # help text, cont.
      tmp = Ops.add(
        tmp,
        _(
          "<p>Synchronization with the NTP server can be done only when the network is configured.</p>"
        )
      )
      tmp
    end

    def ui_enable_disable_widgets(enabled)
      UI.ChangeWidget(Id(:ntp_address), :Enabled, enabled)
      UI.ChangeWidget(Id(:run_service), :Enabled, enabled)
      if !NetworkService.isNetworkRunning
	UI.ChangeWidget(Id(:ntp_now), :Enabled, false)
      else
        UI.ChangeWidget(Id(:ntp_now), :Enabled, enabled)
      end
      UI.ChangeWidget(Id(:ntp_save), :Enabled, enabled)
      if UI.WidgetExists(Id(:ntp_configure)) # bnc#483787
        UI.ChangeWidget(Id(:ntp_configure), :Enabled, enabled)
      end

      nil
    end

    def handle_invalid_hostname(server)
      # translators: error popup
      Popup.Error(Builtins.sformat(_("Invalid NTP server hostname %1"), server))

      nil
    end

    def GetNTPEnabled
      if !Stage.initial
        progress_orig = Progress.set(false)
        NtpClient.Read
        Progress.set(progress_orig)
        NtpClient.ReadSynchronization
      end

      Builtins.y2milestone("synchronize_time %1", NtpClient.synchronize_time)
      Builtins.y2milestone("run_service %1", NtpClient.run_service)
      NtpClient.synchronize_time || Service.Enabled(NtpClient.service_name)
    end

    def ValidateSingleServer(ntp_server)
      if !Address.Check(ntp_server)
        UI.SetFocus(Id(:ntp_address))
        return false
      end

      true
    end

    def AddSingleServer(server)
      idx = NtpClient.findSyncRecord("server", server)

      # -1 means adding new server
      if idx == -1
        Ops.set(NtpClient.selected_record, "address", server)
        Ops.set(NtpClient.selected_record, "type", "server")
      else
        NtpClient.selectSyncRecord(idx)
      end

      NtpClient.storeSyncRecord

      nil
    end


    def MakeProposal()
      ntp_items = []

      #on the running system, read all the data, otherwise firewall
      #and other stuff outside ntp.conf may not be initialized correctly
      #(#375877)
      if !Stage.initial
        progress_orig = Progress.set(false)
        NtpClient.Read
        Progress.set(progress_orig)
      # ntp_selected is true if NTP was proposed during installation (fate#303520)
      elsif !NtpClient.ntp_selected
        NtpClient.ProcessNtpConf
      end

      if NtpClient.config_has_been_read || NtpClient.ntp_selected
        Builtins.y2milestone("ntp_items will be filled from /etc/ntp.conf")
        # grr, GUNS means all of them are used and here we just pick one
        ntp_items = Builtins.maplist(NtpClient.GetUsedNtpServers) do |server|
          Item(Id(server), server)
        end
        # avoid calling Read again (bnc #427712)
        NtpClient.config_has_been_read = true
      end
      if ntp_items == []
        Builtins.y2milestone(
          "Nothing found in /etc/ntp.conf, proposing current timezone-based NTP server list"
        )
        ntp_items = NtpClient.GetNtpServersByCountry(Timezone.GetCountryForTimezone(Timezone.timezone), true)
        NtpClient.config_has_been_read = true
      end
      ntp_items = Builtins.add(ntp_items, "")
      Builtins.y2milestone("ntp_items :%1", ntp_items)
      UI.ChangeWidget(Id(:ntp_address), :Items, ntp_items)

      nil
    end

    # @param [Boolean] first_time when asking for first time, we check if service is running
    # @return should our radio button be selected
    def ui_init(rp, first_time)
      rp = deep_copy(rp)
      cont = VBox(
        VSpacing(0.5),
        HBox(
          HSpacing(3),
          HWeight(
            1,
            VBox(
              VSpacing(0.5),
              Left(
                ComboBox(
                  Id(:ntp_address),
                  Opt(:editable, :hstretch),
                  # combo box label
                  _("&NTP Server Address")
                )
              ),
              VSpacing(0.3),
              HBox(
                HSpacing(0.5),
                # check box label
                Left(
                  CheckBox(
                    Id(:run_service),
                    _("&Run NTP as daemon"),
                    NtpClient.run_service
                  )
                )
              ),
              HBox(
                HSpacing(0.5),
                # check box label
                Left(
                  CheckBox(Id(:ntp_save), _("&Save NTP Configuration"), true)
                )
              )
            )
          ),
          HWeight(
            1,
            VBox(
              Label(""),
              # push button label
              Left(PushButton(Id(:ntp_now), _("S&ynchronize now"))),
              VSpacing(0.3),
              # push button label
              # bnc#449615: only simple config for inst-sys
              Stage.initial ?
                Label("") :
                Left(PushButton(Id(:ntp_configure), _("&Configure..."))),
              Label("")
            )
          )
        )
      )

      UI.ReplaceWidget(rp, cont)

      if !NetworkService.isNetworkRunning
	UI.ChangeWidget(Id(:ntp_now),:Enabled,false);
      end

      # ^ createui0

      # FIXME is it correct? move out?
      ntp_used = first_time && !Stage.initial ?
        GetNTPEnabled() :
        NtpClient.ntp_selected

      UI.ChangeWidget(Id(:ntp_save), :Value, ntp_used)

      MakeProposal()
      ntp_used
    end

    def AskUser
      ret = nil
      ntp_server = Convert.to_string(UI.QueryWidget(Id(:ntp_address), :Value))
      if !ValidateSingleServer(ntp_server)
        ret = :invalid_hostname
      else
        ntp_server2 = Convert.to_string(
          UI.QueryWidget(Id(:ntp_address), :Value)
        )
        AddSingleServer(ntp_server2)
        retval = Convert.to_boolean(WFM.CallFunction("ntp-client"))
        ret = :next if retval
        MakeProposal()
      end
      ret
    end

    def WriteNtpSettings(ntp_servers, ntp_server, run_service)
      ntp_servers = deep_copy(ntp_servers)
      NtpClient.modified = true
      if ntp_servers != []
        Builtins.foreach(ntp_servers) { |server| AddSingleServer(server) }
      else
        AddSingleServer(ntp_server)
      end
      NtpClient.run_service = run_service
      if !run_service
        NtpClient.synchronize_time = true
        NtpClient.sync_interval = 15
      end

      #OK, so we stored the server address
      #In inst-sys we don't need to care further
      #ntp-client_finish will do the job
      #In installed system we must write the settings
      if !Stage.initial
        Wizard.OpenAcceptDialog # FIXME so that the progress does not disturb the dialog to be returned to
        NtpClient.Write
        Wizard.CloseDialog
      end
      true
    end

    # params:
    #   server (taken from UI if empty)
    #   servers (intended to use all of opensuse.pool.ntp.org,
    # 	   but I did not have time to make it work)
    #   write_only (bnc#589296)
    #   ntpdate_only (TODO rename to onetime)
    # return:
    #   `success, `invalid_hostname or `ntpdate_failed
    def Write(param)
      ntp_servers = param["servers"] || []
      ntp_server = param["server"] || ""
      run_service = param["run_service"] || true
      if ntp_server == ""
        # get the value from UI only when it wasn't given as a parameter
        ntp_server = UI.QueryWidget(Id(:ntp_address), :Value)
      end
      return :invalid_hostname if !ValidateSingleServer(ntp_server)

      WriteNtpSettings(ntp_servers, ntp_server, run_service)
      return :success if param["write_only"]

      # One-time adjusment without running the ntp daemon
      # Meanwhile, ntpdate was replaced by sntp
      ntpdate_only = param["ntpdate_only"]

      required_package = "ntp"

      #In 1st stage, schedule packages for installation
      #but not in case user wants to set the time only (F#302917)
      #(ntpdate is in inst-sys so we don't need the package)
      if Stage.initial && !ntpdate_only
        Yast.import "Packages"
        Packages.addAdditionalPackage(required_package)
        # bugzilla #327050
        # Agent for writing /etc/ntp.conf needs to be installed
        # to write the settings at the end of the installation
        Packages.addAdditionalPackage("yast2-ntp-client")
      #Otherwise, prompt user for confirming pkg installation
      elsif !Stage.initial
        if !PackageSystem.CheckAndInstallPackages([required_package])
          Report.Error(
            Builtins.sformat(
              _(
                "Synchronization with NTP server is not possible\nwithout package %1 installed."
              ),
              required_package
            )
          )
        end
      end

      ret = 0
      if NetworkService.isNetworkRunning
        #Only if network is running try to synchronize the ntp server
        Popup.ShowFeedback("", _("Synchronizing with NTP server..."))

        Builtins.y2milestone("Running sntp to sync with %1", ntp_server)

        # -S: do set the system time
        # -t 5: timeout of 5 seconds
        # -K /dev/null: use /dev/null as KoD history file (if not specified,
        #               /var/db/ntp-kod will be used and it doesn't exist)
        # -l <file>: log to a file to not mess text mode installation
        # -c: causes all IP addresses to which ntp_server resolves to be queried in parallel
        ret = SCR.Execute(
                path(".target.bash"),
                "/usr/sbin/sntp -S -K /dev/null -l /var/log/YaST2/sntp.log -t 5 -c '#{String.Quote(ntp_server)}'"
              )
        Builtins.y2milestone("'sntp %1' returned %2", ntp_server, ret)
        Popup.ClearFeedback
      end


      return :ntpdate_failed if ret != 0

      # User wants to more than running sntp (synchronize on boot)
      WriteNtpSettings(ntp_servers, ntp_server, run_service) if !ntpdate_only

      :success
    end

    # ui = UI::UserInput
    def ui_handle(ui)
      redraw = false
      if ui == :ntp_configure
        rv = AskUser()
        if rv == :invalid_hostname
          handle_invalid_hostname(
            UI.QueryWidget(Id(:ntp_address), :Value)
          )
        elsif rv == :next && !Stage.initial
          # show the 'save' status after configuration
          UI.ChangeWidget(Id(:ntp_save), :Value, GetNTPEnabled())
        end
      end
      if ui == :ntp_now
        rv = Write({ "ntpdate_only" => true })
        if rv == :invalid_hostname
          handle_invalid_hostname(UI.QueryWidget(Id(:ntp_address), :Value))
        elsif rv == :success
          redraw = true # update time widgets
        else
          Report.Error(_("Connection to selected NTP server failed."))
        end
      end

      redraw ? :redraw : nil
    end

    def ui_try_save
      argmap = {}
      Ops.set(argmap, "ntpdate_only", false)
      Ops.set(argmap, "run_service", false)
      if UI.QueryWidget(Id(:ntp_save), :Value) == false
        Ops.set(argmap, "ntpdate_only", true)
      end
      if UI.QueryWidget(Id(:run_service), :Value) == true
        Ops.set(argmap, "run_service", true)
      end

      rv = Write(argmap)

      server = Convert.to_string(UI.QueryWidget(Id(:ntp_address), :Value))

      Builtins.y2milestone("ui_try_save argmap %1", argmap)
      if rv == :invalid_hostname
        handle_invalid_hostname(server)
        return false # loop on
      elsif rv == :ntpdate_failed
        # Translators: yes-no popup,
        # ntpdate is a command, %1 is the server address
        if Popup.YesNo(
            Builtins.sformat(
              _(
                "Test query to server '%1' failed.\n" +
                "If server is not yet accessible or network is not configured\n"+
                "click 'No' to ignore. Revisit NTP server configuration?"
              ),
              server
            )
          )
          return false # loop on
        elsif !Ops.get_boolean(argmap, "ntpdate_only", false)
          WriteNtpSettings(
            [],
            server,
            Ops.get_boolean(argmap, "run_service", false)
          ) #may be the server is realy not accessable
        end
      end
      # success, exit
      true
    end
  end
end

Yast::NtpClientProposalClient.new.main
