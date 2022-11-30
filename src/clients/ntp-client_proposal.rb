require "yast"

require "y2ntp_client/widgets/sources_table"

module Yast
  # This is used as the general interface between yast2-country
  # (time,timezone) and yast2-ntp-client.
  class NtpClientProposalClient < Client
    include Yast::Logger

    @sources_table = nil
    @source_add_button = nil
    @source_remove_button = nil
    @source_type_combo = nil

    def main
      Yast.import "UI"
      textdomain "ntp-client"

      Yast.import "Address"
      Yast.import "NetworkService"
      Yast.import "NtpClient"
      Yast.import "Service"
      Yast.import "Stage"
      Yast.import "Package"
      Yast.import "Pkg"
      Yast.import "Popup"
      Yast.import "Progress"
      Yast.import "Report"
      Yast.import "Timezone"
      Yast.import "Wizard"

      @sources_table = Y2NtpClient::Widgets::SourcesTable.new(NtpClient.GetUsedNtpSources)
      @source_add_button = Y2NtpClient::Widgets::SourcesAdd.new
      @source_remove_button = Y2NtpClient::Widgets::SourcesRemove.new
      @source_type_combo = Y2NtpClient::Widgets::SourcesType.new

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
        @ret = NtpClient.dhcp_ntp_servers.map(&:hostname)
      when "MakeProposal"
        @ret = MakeProposal()
      when "Write"
        # compatibility layer for yast-country. Yast-country works with array of servers
        # which were obtained from here via dhcp_ntp_servers call. And dhcp can never
        # provide pool according to @see RFC 2132
        if @param["servers"].is_a?(Array)
          @param["servers"] = @param["servers"].each_with_object({}) do |addr, acc|
            acc[addr] = :server
          end
        end
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
      if Stage.initial
        # help text
        _(
          "<p>Press <b>Synchronize Now</b>, to get your system time set correctly " \
          "using the selected NTP server. If you want to make use of NTP permanently, " \
          "enable the <b>Save NTP Configuration</b> option</p>"
        ) + _(
          "<p>Enabling <b>Run NTP as daemon</b> option, the NTP service will be " \
          "started as daemon. Otherwise the system time will be synchronized periodically. " \
          "The default interval is 15 min. You can change it after installation " \
          "with the <b>yast2 ntp-client module</b>.</p>"
        ) + _(
          "<p>Synchronization with the NTP server can be done only when " \
          "the network is configured.</p>"
        )
      else
        # help text
        _(
          "<p>Using the <b>Configure</b> button, open the advanced NTP configuration.</p>"
        )
      end
    end

    def ui_enable_disable_widgets(enabled)
      UI.ChangeWidget(Id(:ntp_address), :Enabled, enabled) if select_ntp_server

      if Stage.initial
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
        UI.ChangeWidget(Id(:ntp_address), :Enabled, enabled)

        @sources_table.send(enabled ? :enable : :disable)
        @source_add_button.send(enabled ? :enable : :disable)
        @source_remove_button.send(enabled ? :enable : :disable)
        @source_type_combo.send(enabled ? :enable : :disable)
      end
      if UI.WidgetExists(Id(:ntp_configure))
        # bnc#483787
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

      # Once read or proposed any config we consider it as read (bnc#427712)
      NtpClient.config_has_been_read = true

      # if something was already stored internally, clear it and update according to the proposal
      NtpClient.ntp_conf.clear_sources

      # do a proposal - by default add dhcp to proposal
      ntp_sources = dhcp_ntp_items
      ntp_sources.each { |addr, type| NtpClient.ntp_conf.send("add_#{type}".downcase, addr) }
      @sources_table.sources = ntp_sources

      # initialize the combo of suggested ntp sources (not selected to be stored, just hint
      # for user). We use timezone based list of ntp sources in addition to dhcp ones for that
      ntp_sources = ntp_sources.merge(timezone_ntp_items)
      ntp_items = ntp_sources
        .merge(NtpClient.GetUsedNtpSources)
        .keys
        .map { |a| Item(Id(a), a) }
      UI.ChangeWidget(Id(:ntp_address), :Items, ntp_items)

      # get in sync some prefilled values @see sources_table and @see ntp_source_input_widget
      # get in sync proposal and internal state
      @source_type_combo.value = ntp_sources.values.first

      nil
    end

    # Creates a widget representing currently configured ntp servers
    #
    # @return YUI widget
    def ntp_sources_list_table
      to_yui_term(@sources_table)
    end

    # Creates an add button widget
    #
    # Intended for modifying sources table (@see ntp_sources_list_table)
    #
    # @return YUI widget
    def ntp_source_add_button
      to_yui_term(@source_add_button)
    end

    # Creates a remove button widget
    #
    # Intended for modifying sources table (@see ntp_sources_list_table)
    #
    # @return YUI widget
    def ntp_source_remove_button
      to_yui_term(@source_remove_button)
    end

    # Creates a combo for selecting source type
    #
    # Currently supported types are "Pool" or "Server" (@see ntp_sources_list_table)
    #
    # @return YUI widget
    def ntp_source_type_combo
      to_yui_term(@source_type_combo)
    end

    # @param [AbstractWidget] widget a widget from new CWM model class tree
    # @return [::CWM::UITerm] term for libyui
    def to_yui_term(widget)
      # Warning: Close your eyes
      # Still looking? OK, so
      # - we're going to translate CWM widgets
      # - we have to bcs only reason for this (and related methods) is that it creates
      # part of dialog (in fact modifies on the fly) which is constructed in yast2-country.
      # We cannot use whole power of CWM and have to "emulate it"
      # - involved methods are at least ui_init (creates relevant part of the dialog) and
      # ui_handle (processes user's input)
      CWM.prepareWidget(widget.cwm_definition)["widget"]
      # You can open eyes now
    end

    # @param [Yast::Term] replace_point id of replace point which should be used
    # @param [Boolean] first_time when asking for first time, we check if service is running
    # @return should our radio button be selected
    def ui_init(replace_point, first_time)
      log.info("ui_init - enter")

      if Stage.initial
        # TRANSLATORS: push button label
        ntp_server_action_widget = PushButton(Id(:ntp_now), _("S&ynchronize now"))
        save_run_widget = VBox(
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
      else
        # TRANSLATORS: push button label
        # bnc#449615: only simple config for inst-sys
        ntp_server_action_widget = Left(PushButton(Id(:ntp_configure), _("&Configure...")))
        save_run_widget = VBox()
      end

      cont = HBox(
        VBox(
          Left(
            ntp_sources_list_table
          ),
          Left(
            VSquash(
              HBox(
                Bottom(
                  ntp_source_type_combo
                ),
                Bottom(
                  ntp_source_input_widget
                ),
                Bottom(
                  ntp_source_add_button
                )
              )
            )
          )
        ),
        Top(
          VBox(
            Left(
              ntp_server_action_widget
            ),
            Left(
              ntp_source_remove_button
            ),
            VSpacing(1),
            save_run_widget
          )
        )
      )

      UI.ReplaceWidget(replace_point, cont)

      if Stage.initial && !NetworkService.isNetworkRunning
        UI.ChangeWidget(Id(:ntp_now), :Enabled, false)
      end

      # ^ createui0

      # FIXME: is it correct? move out?
      ntp_used = (first_time && !Stage.initial) ? GetNTPEnabled() : NtpClient.ntp_selected

      UI.ChangeWidget(Id(:ntp_save), :Value, ntp_used) if Stage.initial

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
    # @param ntp_sources [Hash<String, Symbol>] ntp sources ({ "address" => <:pool|:server> })
    # @param ntp_server [String] fallback server that is used if `ntp_servers` param is empty.
    # @param run_service [Boolean] define if synchronize with systemd services or via systemd timer
    # @return true
    def WriteNtpSettings(ntp_sources, ntp_server, run_service)
      ntp_sources = deep_copy(ntp_sources)
      NtpClient.modified = true
      ntp_sources << ntp_server if ntp_sources.empty?

      if !ntp_sources.empty?
        # Servers list available. So we are writing them.
        NtpClient.ntp_conf.clear_sources
        ntp_sources.each_pair do |addr, type|
          NtpClient.ntp_conf.send("add_#{type}", addr)
        end
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
    # @option params [Hash<String, Symbol>] ntp sources ( { "address" => <:pool | :server> })
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
      ntp_servers = params.fetch("servers", NtpClient.GetUsedNtpSources)
      run_service = params.fetch("run_service", NtpClient.run_service)

      return :invalid_hostname if !ntp_server.empty? && !ValidateSingleServer(ntp_server)

      add_or_install_required_package unless params["write_only"]

      WriteNtpSettings(ntp_servers, ntp_server, run_service) unless params["ntpdate_only"]

      return :success if params["write_only"]

      # Only if network is running try to synchronize
      # the ntp server.
      if NetworkService.isNetworkRunning && !Service.Active(NtpClient.service_name)
        ntp_servers = [ntp_server] + ntp_servers.keys
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
    def ui_handle(input)
      redraw = false
      case input
      when @source_add_button.widget_id
        ntp_source_address = UI.QueryWidget(Id(:ntp_address), :Value)
        ntp_source_type = @source_type_combo.value
        ntp_source = { ntp_source_address => ntp_source_type }

        NtpClient.ntp_conf.send("add_#{ntp_source_type}".downcase, ntp_source_address)

        @sources_table.sources = @sources_table.sources.merge(ntp_source)
      when @source_remove_button.widget_id
        ntp_source_id = @sources_table.value

        @sources_table.remove_item(ntp_source_id)
      when :ntp_configure
        rv = AskUser()
        if rv == :invalid_hostname
          handle_invalid_hostname(
            UI.QueryWidget(Id(:ntp_address), :Value)
          )
        elsif rv == :next && !Stage.initial
          # Updating UI for the changed ntp servers
          ui_init(Id(:rp), false)

          if Stage.initial
            # show the 'save' status after configuration
            UI.ChangeWidget(Id(:ntp_save), :Value, GetNTPEnabled())
          end
        end
      when :ntp_now
        rv = Write("ntpdate_only" => true)
        if rv == :invalid_hostname
          handle_invalid_hostname(UI.QueryWidget(Id(:ntp_address), :Value))
        elsif rv == :success
          redraw = true # update time widgets
        else
          Report.Error(_("Connection to selected NTP server failed."))
        end
      when :accept
        # checking if chrony is available for installation.
        if Stage.initial && UI.QueryWidget(Id(:ntp_save), :Value) == true &&
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
      Ops.set(argmap, "run_service", NtpClient.run_service)
      if Stage.initial
        Ops.set(argmap, "ntpdate_only", true) if UI.QueryWidget(Id(:ntp_save), :Value) == false
        Ops.set(argmap, "run_service", true) if UI.QueryWidget(Id(:run_service), :Value)

        argmap["servers"] = @sources_table.sources
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
      elsif !Package.CheckAndInstallPackages([NtpClientClass::REQUIRED_PACKAGE])
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
    # @return [Hash<String, Symbol>] ntp address and its type (server / pool)
    def timezone_ntp_items
      timezone_country = Timezone.GetCountryForTimezone(Timezone.timezone)
      servers = NtpClient.country_ntp_servers(timezone_country)
      # Select the first occurrence of pool.ntp.org as the default option (bnc#940881)
      servers.find { |s| s.hostname.end_with?("pool.ntp.org") }
      servers.each_with_object({}) do |server, acc|
        # currently no way how to safely decide whether the source is pool or server
        # so use pool as default (either it is from pool.ntp.org or we cannot decide for sure)
        acc[server.hostname] = :pool
      end
    end

    # List of dhcp ntp servers Yast::Term items with the ntp address ID and
    # label
    #
    # @return [Hash<String, Symbol>] ntp address and its type (server / pool)
    def dhcp_ntp_items
      NtpClient.dhcp_ntp_servers.each_with_object({}) do |server, acc|
        # dhcp can contain only an IP addresses in option 042
        # (This option specifies a list of IP addresses indicating NTP
        # servers available to the client. @see RFC 2132)
        acc[server.hostname] = :server
      end
    end

    # List of ntp servers Yast::Term items with the ntp address ID and label
    #
    # @return [Hash<String, Symbol>] ntp address and its type (server / pool)
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
        ret = fallback_ntp_items.keys.any? do |item|
          item == NtpClient.GetUsedNtpServers.first
        end
      end
      ret
    end

    # Widget for entering custom ntp source configuration
    def ntp_source_input_widget
      MinWidth(
        20,
        ComboBox(
          Id(:ntp_address),
          Opt(:editable, :hstretch),
          # TRANSLATORS: combo box label
          _("&NTP Server Address")
        )
      )
    end
  end
end

Yast::NtpClientProposalClient.new.main
