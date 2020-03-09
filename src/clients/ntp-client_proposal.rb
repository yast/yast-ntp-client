# encoding: utf-8

require "yast"

module Yast
  # This is used as the general interface between yast2-country
  # (time,timezone) and yast2-ntp-client.
  class NtpClientProposalClient < Client
    include Yast::Logger

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
      Yast.import "Pkg"
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

      # FIXME: must go to module to preserve value
      @ntp_was_used = false

      case @func
      when "GetNTPEnabled"
        @ret = GetNTPEnabled()
      when "SetUseNTP"
        NtpClient.ntp_selected = Ops.get_boolean(@param, "ntp_used", false)
        @ret = true
      when "dhcp_ntp_servers"
        @ret = NtpClient.dhcp_ntp_servers
      when "MakeProposal"
        @ret = MakeProposal()
      when "Write"
        @ret = Write(@param)
      when "ui_help_text"
        @ret = ui_help_text
      when "ui_init"
        @rp = Ops.get_term(@param, "replace_point") { Id(:rp) }
        @ft = Ops.get_boolean(@param, "first_time", false)
        @ret = ui_init(@rp, @ft)
      when "ui_try_save"
        @ret = ui_try_save
      when "ui_enable_disable_widgets"
        @ret = ui_enable_disable_widgets(
          Ops.get_boolean(@param, "enabled", false)
        )
      when "ui_handle"
        @ret = ui_handle(Ops.get(@param, "ui"))
      else
        log.error("Not known called func #{@func}")
      end

      deep_copy(@ret)
    end

    def ui_help_text
      # help text
      tmp = _(
        "<p>Press <b>Synchronize Now</b>, to get your system time set correctly " \
        "using the selected NTP server. If you want to make use of NTP permanently, " \
        "enable the <b>Save NTP Configuration</b> option</p>"
      )

      tmp = Ops.add(
        tmp,
        _(
          "<p>Enabling <b>Run NTP as daemon</b> option, the NTP service will be " \
          "started as daemon. Otherwise the system time will be synchronized periodically. " \
          "The default interval is 15 min. You can change it after installation " \
          "with the <b>yast2 ntp-client module</b>.</p>"
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
          "<p>Synchronization with the NTP server can be done only when " \
          "the network is configured.</p>"
        )
      )
      tmp
    end

    def ui_enable_disable_widgets(enabled)
      UI.ChangeWidget(Id(:ntp_address), :Enabled, enabled) if select_ntp_server
      UI.ChangeWidget(Id(:run_service), :Enabled, enabled)
      # FIXME: With chronyd, we cannot synchronize if the service is already
      # running, we could force a makestep in this case, but then the button
      # should be reworded and maybe the user should confirm it (bsc#1087048)
      if !NetworkService.isNetworkRunning || Service.Active(NtpClient.service_name)
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

    def MakeProposal
      # On the running system, read all the data, otherwise firewall and other
      # stuff outside ntp.conf may not be initialized correctly (#375877)
      if !Stage.initial
        progress_orig = Progress.set(false)
        NtpClient.Read
        Progress.set(progress_orig)
      # ntp_selected is true if NTP was proposed during installation (fate#303520)
      elsif !NtpClient.ntp_selected
        NtpClient.ProcessNtpConf
      end

      if select_ntp_server
        ntp_items = fallback_ntp_items
        # Once read or proposed any config we consider it as read (bnc#427712)
        NtpClient.config_has_been_read = true

        log.info "ntp_items :#{ntp_items}"
        UI.ChangeWidget(Id(:ntp_address), :Items, ntp_items)
      end

      nil
    end

    # @param [Boolean] first_time when asking for first time, we check if service is running
    # @return should our radio button be selected
    def ui_init(rp, first_time)
      rp = deep_copy(rp)

      if select_ntp_server
        ntp_server_widget = ComboBox(
          Id(:ntp_address),
          Opt(:editable, :hstretch),
          # TRANSLATORS: combo box label
          _("&NTP Server Address")
        )
      else
        # Only show all ntp servers
        text = _("Synchronization Servers:\n").dup
        counter = NtpClient.GetUsedNtpServers.size > 3 ? 3 : NtpClient.GetUsedNtpServers.size
        counter.times do |i|
          text << NtpClient.GetUsedNtpServers[i]
          text << "\n"
        end
        if NtpClient.GetUsedNtpServers.size > 3
          # TRANSLATOR %{count} number of additional servers
          text << format(_("... (%{count} more servers)"),
            count: (NtpClient.GetUsedNtpServers.size - counter))
        end
        ntp_server_widget = Label(text)
      end

      cont = VBox(
        VSpacing(0.5),
        HBox(
          HSpacing(3),
          HWeight(
            1,
            Left(
              ntp_server_widget
            )
          ),
          HWeight(
            1,
            VBox(
              # In TextMode and empty label is not filling an extra space, so
              # an explicit vertical space was added in order to move down the
              # push button being aligned with the combo box input.
              UI.TextMode ? VSpacing(1) : Label(""),
              # TRANSLATORS: push button label
              Left(PushButton(Id(:ntp_now), _("S&ynchronize now")))
            )
          )
        ),
        HBox(
          HSpacing(3),
          HWeight(
            1,
            VBox(
              HBox(
                HSpacing(0.5),
                # TRANSLATORS: check box label
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
                # TRANSLATORS: check box label
                Left(
                  CheckBox(Id(:ntp_save), _("&Save NTP Configuration"), true)
                )
              )
            )
          ),
          HWeight(
            1,
            VBox(
              # TRANSLATORS: push button label
              # bnc#449615: only simple config for inst-sys
              Stage.initial ? Label("") : Left(PushButton(Id(:ntp_configure), _("&Configure..."))),
              Label("")
            )
          )
        )
      )

      UI.ReplaceWidget(rp, cont)

      UI.ChangeWidget(Id(:ntp_now), :Enabled, false) if !NetworkService.isNetworkRunning

      # ^ createui0

      # FIXME: is it correct? move out?
      ntp_used = first_time && !Stage.initial ? GetNTPEnabled() : NtpClient.ntp_selected

      UI.ChangeWidget(Id(:ntp_save), :Value, ntp_used)

      MakeProposal()
      ntp_used
    end

    def AskUser
      ret = nil
      if select_ntp_server
        # The user can select ONE ntp server.
        # So we Initialize the ntp client module with the selected ntp server.
        ntp_server = Convert.to_string(UI.QueryWidget(Id(:ntp_address), :Value))
        return :invalid_hostname unless ValidateSingleServer(ntp_server)
        NtpClient.ntp_conf.clear_pools
        NtpClient.ntp_conf.add_pool(ntp_server)
      end
      # Calling ntp client module.
      ret = :next if WFM.CallFunction("ntp-client")
      # Initialize the rest
      MakeProposal()

      ret
    end

    # Writes configuration for ntp client.
    # @param ntp_servers [Array<String>] list of servers to configure as ntp sync sources
    # @param ntp_server [String] fallback server that is used if `ntp_servers` param is empty.
    # @param run_service [Boolean] define if synchronize with systemd services or via cron sync
    # @return true
    def WriteNtpSettings(ntp_servers, ntp_server, run_service)
      ntp_servers = deep_copy(ntp_servers)
      NtpClient.modified = true
      NtpClient.ntp_conf.clear_pools
      ntp_servers << ntp_server if ntp_servers.empty?
      ntp_servers.each do |server|
        NtpClient.ntp_conf.add_pool(server)
      end
      if run_service
        NtpClient.run_service = true
        NtpClient.synchronize_time = false
      else
        NtpClient.run_service = false
        NtpClient.synchronize_time = true
        NtpClient.sync_interval = NtpClientClass::DEFAULT_SYNC_INTERVAL
      end

      # OK, so we stored the server address
      # In inst-sys we don't need to care further
      # ntp-client_finish will do the job
      # In installed system we must write the settings
      if !Stage.initial
        # FIXME: so that the progress does not disturb the dialog to be returned to
        Wizard.OpenAcceptDialog
        NtpClient.Write
        Wizard.CloseDialog
      end
      true
    end

    # Writes the NTP settings
    #
    # @param [Hash] params
    # @option params [String] "server" The NTP server address, taken from the UI if empty
    # @option params [Array<String>] "servers" A collection of NTP servers
    # @option params [Boolean] "run_service" Whether service should be active and enable
    # @option params [Boolean] "write_only" If only is needed to write the settings, (bnc#589296)
    # @option params [Boolean] "ntpdate_only" ? TODO: rename to onetime
    #
    # @return [Symbol] :invalid_hostname, when a not valid ntp_server is given
    #                  :ntpdate_failed, when the ntp sychronization fails
    #                  :success, when settings (and sync if proceed) were performed successfully
    def Write(params)
      log.info "ntp client proposal Write with #{params.inspect}"

      # clean params
      params.compact!

      ntp_server  = params.fetch("server", "")
      ntp_servers = params.fetch("servers", NtpClient.GetUsedNtpServers)
      run_service = params.fetch("run_service", NtpClient.run_service)

      # Get the ntp_server value from UI only if isn't present (probably wasn't given as parameter)
      if ntp_server.strip.empty? && select_ntp_server
        ntp_server = UI.QueryWidget(Id(:ntp_address), :Value) || ""
      end

      if !ntp_server.empty? && !ValidateSingleServer(ntp_server)
        return :invalid_hostname
      end

      add_or_install_required_package unless params["write_only"]

      WriteNtpSettings(ntp_servers, ntp_server, run_service) unless params["ntpdate_only"]

      return :success if params["write_only"]

      # Only if network is running try to synchronize
      # the ntp server.
      if NetworkService.isNetworkRunning && !Service.Active(NtpClient.service_name)
        ntp_servers = [ntp_server]
        if !select_ntp_server
          # Taking also the rest of the ntp servers, configured in the ntp client module.
          ntp_servers += NtpClient.GetUsedNtpServers unless NtpClient.GetUsedNtpServers.nil?
        end
        ntp_servers.delete("")
        ntp_servers.uniq
        exit_code = 0
        ntp_servers.each do |server|
          Popup.ShowFeedback("", _("Synchronizing with NTP server...") + server)
          exit_code = NtpClient.sync_once(server)
          Popup.ClearFeedback
          break if exit_code.zero?
        end

        return :ntpdate_failed unless exit_code.zero?
      end

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
          # Updating UI for the changed ntp servers
          ui_init(Id(:rp), false)
          # show the 'save' status after configuration
          UI.ChangeWidget(Id(:ntp_save), :Value, GetNTPEnabled())
        end
      end
      if ui == :ntp_now
        rv = Write("ntpdate_only" => true)
        if rv == :invalid_hostname
          handle_invalid_hostname(UI.QueryWidget(Id(:ntp_address), :Value))
        elsif rv == :success
          redraw = true # update time widgets
        else
          Report.Error(_("Connection to selected NTP server failed."))
        end
      end
      if ui == :accept && Stage.initial
        # checking if chrony is available for installation.
        if UI.QueryWidget(Id(:ntp_save), :Value) == true &&
            !Pkg.IsAvailable(NtpClientClass::REQUIRED_PACKAGE)
          Report.Error(Builtins.sformat(
            # TRANSLATORS: Popup message. %1 is the missing package name.
            _("Cannot save NTP configuration because the package %1 is not available."),
            NtpClientClass::REQUIRED_PACKAGE
          ))
          UI.ChangeWidget(Id(:ntp_save), :Value, false)
          redraw = true
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

      # The user has not had the possibility to change the ntp server.
      # So we are done here.
      return true unless select_ntp_server

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
              "Test query to server '%1' failed.\n" \
              "If server is not yet accessible or network is not configured\n" \
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
          ) # may be the server is realy not accessable
        end
      end
      # success, exit
      true
    end

  private

    def add_or_install_required_package
      # In 1st stage, schedule packages for installation
      if Stage.initial
        Yast.import "Packages"
        Packages.addAdditionalPackage(NtpClientClass::REQUIRED_PACKAGE)
      # Otherwise, prompt user for confirming pkg installation
      elsif !PackageSystem.CheckAndInstallPackages([NtpClientClass::REQUIRED_PACKAGE])
        Report.Error(
          Builtins.sformat(
            _("Synchronization with NTP server is not possible\nwithout package %1 installed."),
            NtpClientClass::REQUIRED_PACKAGE
          )
        )
      end
    end

    # Public list of ntp servers Yast::Term items with the ntp address ID and
    # label
    #
    # @return [Array<Yast::Term>] ntp address Item
    def timezone_ntp_items
      timezone_country = Timezone.GetCountryForTimezone(Timezone.timezone)
      NtpClient.GetNtpServersByCountry(timezone_country, true)
    end

    # List of dhcp ntp servers Yast::Term items with the ntp address ID and
    # label
    #
    # @return [Array<Yast::Term>] ntp address table Item
    def dhcp_ntp_items
      NtpClient.dhcp_ntp_servers.map { |s| Item(Id(s), s) }
    end

    # List of ntp servers Yast::Term items with the ntp address ID and label
    #
    # @return [Array<Yast::Term>] ntp address table Item
    def fallback_ntp_items
      return @cached_fallback_ntp_items if @cached_fallback_ntp_items
      @cached_fallback_ntp_items = dhcp_ntp_items
      if !@cached_fallback_ntp_items.empty?
        log.info("Proposing NTP server list provided by DHCP")
      else
        log.info("Proposing current timezone-based NTP server list")
        @cached_fallback_ntp_items = timezone_ntp_items
      end
      @cached_fallback_ntp_items
    end

    # Checking if the user can select one ntp server from the list
    # of proposed servers.
    # It does not make sense if there are more than one ntp server
    # defined.
    #
    # @return [Boolean] true if the user should select a server
    def select_ntp_server
      ret = NtpClient.GetUsedNtpServers.nil? || NtpClient.GetUsedNtpServers.empty?
      # It could be that the user has defined an own ntp server in the ntp-client
      # module which is not defined in the combo box. In that case we do not offer
      # a selection. The user should go back to ntp-client to change it.
      if NtpClient.GetUsedNtpServers.size == 1
        ret = fallback_ntp_items.any? do |item|
          item.params[1] == NtpClient.GetUsedNtpServers.first
        end
      end
      ret
    end
  end
end

Yast::NtpClientProposalClient.new.main
