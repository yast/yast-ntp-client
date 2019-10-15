# File:  modules/NtpClient.ycp
# Package:  Configuration of ntp-client
# Summary:  Data for configuration of ntp-client, input and output functions.
# Authors:  Jiri Srain <jsrain@suse.cz>
#
# $Id$
#
# Representation of the configuration of ntp-client.
# Input and output routines.
require "yast"
require "yaml"
require "cfa/chrony_conf"
require "yast2/target_file" # required to cfa work on changed scr
require "ui/text_helpers"

module Yast
  class NtpClientClass < Module
    include Logger
    include ::UI::TextHelpers

    # the default synchronization interval in minutes when running in the manual
    # sync mode ("Synchronize without Daemon" option, ntp started from cron)
    # Note: the UI field currently uses maximum of 60 minutes
    DEFAULT_SYNC_INTERVAL = 5

    # the default netconfig policy for ntp
    DEFAULT_NTP_POLICY = "auto".freeze

    # List of servers defined by the pool.ntp.org to get random ntp servers
    #
    # @see #http://www.pool.ntp.org/
    RANDOM_POOL_NTP_SERVERS = ["0.pool.ntp.org", "1.pool.ntp.org", "2.pool.ntp.org"].freeze

    NTP_FILE = "/etc/chrony.conf".freeze

    # The cron file name for the synchronization.
    CRON_FILE = "/etc/cron.d/suse-ntp_synchronize".freeze

    UNSUPPORTED_AUTOYAST_OPTIONS = [
      "configure_dhcp",
      "peers",
      "restricts",
      "start_at_boot",
      "start_in_chroot",
      "sync_interval",
      "synchronize_time"
    ].freeze

    # Package which is needed for saving NTP configuration into system
    REQUIRED_PACKAGE = "chrony".freeze

    def main
      textdomain "ntp-client"

      Yast.import "Directory"
      Yast.import "FileUtils"
      Yast.import "Lan"
      Yast.import "Language"
      Yast.import "Message"
      Yast.import "Mode"
      Yast.import "NetworkInterfaces"
      Yast.import "PackageSystem"
      Yast.import "Popup"
      Yast.import "Progress"
      Yast.import "ProductFeatures"
      Yast.import "Report"
      Yast.import "Service"
      Yast.import "SLPAPI"
      Yast.import "Stage"
      Yast.import "String"
      Yast.import "Summary"
      Yast.import "UI"

      # Abort function
      # return boolean return true if abort
      @AbortFunction = nil

      # Data was modified?
      @modified = false

      # Write only, used during autoinstallation.
      # Don't run services and SuSEconfig, it's all done at one place.
      @write_only = false

      # Should the daemon be started when system boots?
      @run_service = true

      # Should the time synchronized periodicaly?
      @synchronize_time = false

      # The interval of synchronization in minutes.
      @sync_interval = DEFAULT_SYNC_INTERVAL

      # Service names of the NTP daemon
      @service_name = "chronyd"

      # "chrony-wait" service has also to be handled in order to ensure that
      # "chronyd" is working correctly and do not depend on the network status.
      # bsc#1137196, bsc#1129730
      @wait_service_name = "chrony-wait"

      # Netconfig policy: for merging and prioritizing static and DHCP config.
      # https://github.com/openSUSE/sysconfig/blob/master/doc/README.netconfig
      # https://github.com/openSUSE/sysconfig/blob/master/config/sysconfig.config-network
      @ntp_policy = DEFAULT_NTP_POLICY

      # Active Directory controller
      @ad_controller = ""

      # Required packages
      @required_packages = [REQUIRED_PACKAGE]

      # List of known NTP servers
      # server address -> information
      #  address: the key repeated
      #  country: CC (uppercase)
      #  location: for displaying
      #  ...: (others are unused)
      @ntp_servers = nil

      # Mapping between country codes and country names ("CZ" -> "Czech Republic")
      @country_names = nil

      @config_has_been_read = false

      # for lazy loading
      @countries_already_read = false
      @known_countries = {}

      @random_pool_servers = RANDOM_POOL_NTP_SERVERS

      # helper variable to hold config from ntp client proposal
      @ntp_selected = false
    end

    # CFA instance for reading/writing /etc/chrony.conf
    def ntp_conf
      @ntp_conf ||= CFA::ChronyConf.new
    end

    # Abort function
    # @return blah blah lahjk
    def Abort
      @AbortFunction.nil? ? false : @AbortFunction.call == true
    end

    def go_next
      return false if Abort()

      Progress.NextStage if progress?
      true
    end

    def progress?
      Mode.normal
    end

    # Synchronize against specified server only one time and does not modify
    # any configuration
    # @param server [String] to sync against
    # @return [Integer] exit code of sync command
    def sync_once(server)
      log.info "Running one time sync with #{server}"

      # -q: set system time and quit
      # -t: timeout in seconds
      # -l <file>: log to a file to not mess text mode installation
      # -c: causes all IP addresses to which ntp_server resolves to be queried in parallel
      ret = SCR.Execute(
        path(".target.bash_output"),
        # TODO: ensure that we can use always pool instead of server?
        "/usr/sbin/chronyd -q -t 30 'pool #{String.Quote(server)} iburst'"
      )
      log.info "'one-time chrony for #{server}' returned #{ret}"

      ret["exit"]
    end

    # Given a country code and a location returns a hash with pool
    # ntp address for given country, country code and location
    # @return [Hash{String => String}] ntp pool address for given country
    def MakePoolRecord(country_code, location)
      mycc = country_code.downcase
      # There is no gb.pool.ntp.org only uk.pool.ntp.org
      mycc = "uk" if mycc == "gb"
      {
        "address"  => "#{mycc}.pool.ntp.org",
        "country"  => country_code,
        "location" => location
      }
    end

    # Get the list of known NTP servers
    # @return a list of known NTP servers
    def GetNtpServers
      update_ntp_servers! if @ntp_servers.nil?

      deep_copy(@ntp_servers)
    end

    # Get the mapping between country codes and names ("CZ" -> "Czech Republic")
    # @return a map the country codes and names mapping
    def GetCountryNames
      if @country_names.nil?
        @country_names = Convert.convert(
          Builtins.eval(SCR.Read(path(".target.yast2"), "country.ycp")),
          from: "any",
          to:   "map <string, string>"
        )
      end
      if @country_names.nil?
        Builtins.y2error("Failed to read country names")
        @country_names = {}
      end
      deep_copy(@country_names)
    end

    # Get list of public NTP servers for a country
    # @param [String] country two-letter country code
    # @param [Boolean] terse_output display additional data (location etc.)
    # @return [Array] of servers (usable as combo-box items)
    def GetNtpServersByCountry(country, terse_output)
      country_names = {}
      servers = GetNtpServers()
      if country.to_s != ""
        servers.select! { |_server, attrs| attrs["country"] == country }
        # bnc#458917 add country, in case data/country.ycp does not have it
        pool_country_record = MakePoolRecord(country, "")
        servers[pool_country_record["address"]] = pool_country_record
      else
        country_names = GetCountryNames()
      end

      default = false
      servers.map do |server, attrs|
        # Select the first occurrence of pool.ntp.org as the default option (bnc#940881)
        selected = default ? false : default = server.end_with?("pool.ntp.org")

        next Item(Id(server), server, selected) if terse_output

        country_label = country.empty? ? country_names[attrs["country"]] || attrs["country"] : ""

        label = server + country_server_label(attrs["location"].to_s, country_label.to_s)

        Item(Id(server), label, selected)
      end
    end

    def read_ntp_conf
      if !FileUtils.Exists(NTP_FILE)
        log.error("File #{NTP_FILE} does not exist")
        return false
      end

      begin
        ntp_conf.load
      rescue StandardError => e
        log.error("Failed to read #{NTP_FILE}: #{e.message}")
        return false
      end

      true
    end

    # Read and parse /etc/ntp.conf
    # @return true on success
    def ProcessNtpConf
      if @config_has_been_read
        log.info "Configuration has been read already, skipping."
        return false
      end

      return false unless read_ntp_conf

      @config_has_been_read = true

      true
    end

    # Read the synchronization status, fill
    # synchronize_time and sync_interval variables
    # Return updated value of synchronize_time
    def ReadSynchronization
      crontab = SCR.Read(path(".cron"), CRON_FILE, "")
      log.info("NTP Synchronization crontab entry: #{crontab}")
      cron_entry = (crontab || []).fetch(0, {}).fetch("events", []).fetch(0, {})
      @synchronize_time = cron_entry["active"] == "1"

      sync_interval_entry = cron_entry.fetch("minute", "*/#{DEFAULT_SYNC_INTERVAL}")
      log.info("MINUTE #{sync_interval_entry}")

      @sync_interval = sync_interval_entry.tr("^[0-9]", "").to_i
      log.info("SYNC_INTERVAL #{@sync_interval}")

      @synchronize_time
    end

    # Read all ntp-client settings
    # @return true on success
    def Read
      return true if @config_has_been_read

      # We do not set help text here, because it was set outside
      new_read_progress if progress?

      # read network configuration
      return false if !go_next

      progress_orig = Progress.set(false)
      NetworkInterfaces.Read
      Progress.set(progress_orig)

      read_policy!
      GetNtpServers()
      GetCountryNames()

      # read current settings
      return false if !go_next

      if !Mode.installation && !PackageSystem.CheckAndInstallPackagesInteractive(["chrony"])
        log.info("PackageSystem::CheckAndInstallPackagesInteractive failed")
        return false
      end

      @run_service = Service.Enabled(@service_name)

      # Poke to /var/lib/YaST if there is Active Directory controller address dumped in .ycp file
      read_ad_address!

      ProcessNtpConf()
      ReadSynchronization()

      return false if !go_next

      Progress.Title(_("Finished")) if progress?

      return false if Abort()

      @modified = false
      true
    end

    # Function returns list of NTP servers used in the configuration.
    #
    # @return [Array<String>] of servers
    def GetUsedNtpServers
      ntp_conf.pools.keys
    end

    # Write all ntp-client settings
    # @return true on success
    def Write
      # We do not set help text here, because it was set outside
      new_write_progress if progress?

      # write settings
      return false if !go_next

      Report.Error(Message.CannotWriteSettingsTo("/etc/chrony.conf")) if !write_ntp_conf

      write_and_update_policy

      # restart daemon
      return false if !go_next

      check_service

      update_cron_settings

      return false if !go_next

      Progress.Title(_("Finished")) if progress?

      !Abort()
    end

    # Get all ntp-client settings from the first parameter
    # (For use by autoinstallation.)
    # @param [Hash] settings The YCP structure to be imported.
    # @return [Boolean] True on success
    def Import(settings)
      log.info "Import with #{settings}"

      unsupported = UNSUPPORTED_AUTOYAST_OPTIONS.select { |o| settings.key?(o) }
      if !unsupported.empty?
        unsupported_error(unsupported)
        return false
      end

      sync = (settings["ntp_sync"] || "systemd").strip
      case sync
      when "systemd"
        @run_service = true
        @synchronize_time = false
      when /[0-9]/
        @run_service = false
        @synchronize_time = true
        @sync_interval = sync.to_i
        # if wrong number is passed log it and use default
        if !(1..59).cover?(@sync_interval)
          log.error "Invalid interval in sync interval #{@sync_interval}"
          @sync_interval = DEFAULT_SYNC_INTERVAL
        end
      when /manual/
        @run_service = false
        @synchronize_time = false
      else
        # TRANSLATORS: error report. %s stands for invalid content.
        Yast::Report.Error(format(_("Invalid value for ntp_sync key: '%s'"), sync))
        return false
      end

      @modified = true
      @ntp_policy = settings["ntp_policy"] || DEFAULT_NTP_POLICY
      ntp_conf.clear_pools
      (settings["ntp_servers"] || []).each do |server|
        options = {}
        options["iburst"] = nil if server["iburst"]
        options["offline"] = nil if server["offline"]
        address = server["address"]
        log.info "adding server '#{address.inspect}' with options #{options.inspect}"
        ntp_conf.add_pool(address, options)
      end

      true
    end

    # Merges config to existing system configuration. It is useful for delayed write.
    # When it at first set values, then chrony is installed and then it writes. So
    # before write it will merge to system. Result is that it keep majority of config
    # untouched and modify what is needed.
    # What it mean is that if it set values, it works on parsed configuration file,
    # but if package is not yet installed, then it creates new configuration file
    # which is missing many stuff like comments or values that yast2-ntp-client does not touch.
    # So if package is installed later, then this method re-apply changes on top of newly parsed
    # file.
    def merge_to_system
      config = Export()
      Read()
      Import(config)
    end

    # Summary text about ntp configuration
    def Summary
      result = ""
      sync_line = if @run_service
        _("The NTP daemon starts when starting the system.")
      elsif @synchronize_time
        # TRANSLATORS %i is number of seconds.
        format(_("The NTP will be synchronized every %i seconds."), @sync_interval)
      else
        _("The NTP won't be automatically synchronized.")
      end
      result = Yast::Summary.AddLine(result, sync_line)
      policy_line = case @ntp_policy
      when "auto"
        _("Combine static and DHCP configuration.")
      when ""
        _("Static configuration only.")
      else
        format(_("Custom configuration policy: '%s'."), @ntp_policy)
      end
      result = Yast::Summary.AddLine(result, policy_line)
      # TRANSLATORS: summary line. %s is formatted list of addresses.
      servers_line = format(_("Servers: %s."), GetUsedNtpServers().join(", "))
      result = Yast::Summary.AddLine(result, servers_line)

      result
    end

    # Dump the ntp-client settings to a single map
    # (For use by autoinstallation.)
    # @return [Hash] Dumped settings (later acceptable by Import ())
    def Export
      sync_value = if @run_service
        "systemd"
      elsif @synchronize_time
        @sync_interval.to_s
      else
        "manual"
      end
      pools_export = ntp_conf.pools.map do |(address, options)|
        {
          "address" => address,
          "iburst"  => options.key?("iburst"),
          "offline" => options.key?("offline")
        }
      end
      {
        "ntp_sync"    => sync_value,
        "ntp_policy"  => @ntp_policy,
        "ntp_servers" => pools_export
      }
    end

    # Test if a specified NTP server is reachable by IPv4 or IPv6 (bsc#74076),
    # Firewall could have been blocked IPv6
    # @param [String] server string host name or IP address of the NTP server
    # @return [Boolean] true if NTP server answers properly
    def reachable_ntp_server?(server)
      ntp_test(server) || ntp_test(server, 6)
    end

    # Test NTP server answer for a given IP version.
    # @param [String] server string host name or IP address of the NTP server
    # @param [Integer] ip_version ip version to use (4 or 6)
    # @return [Boolean] true if stderr does not include lookup error and exit
    # code is 0
    def ntp_test(server, ip_version = 4)
      output = SCR.Execute(
        path(".target.bash_output"),
        # -t : seconds of timeout
        # -Q: print only offset, if failed exit is non-zero
        "LANG=C /usr/sbin/chronyd -#{ip_version} -t 30 -Q 'pool #{server} iburst'"
      )

      Builtins.y2milestone("chronyd test response: #{output}")

      output["exit"] == 0
    end

    # Handle UI of NTP server test answers
    # @param [String] server string host name or IP address of the NTP server
    # @param [Symbol] verbosity `no_ui: ..., `transient_popup: pop up while scanning,
    #                  `result_popup: also final pop up about the result
    # @return [Boolean] true if NTP server answers properly
    def TestNtpServer(server, verbosity)
      return reachable_ntp_server?(server) if verbosity == :no_ui

      ok = false
      Yast::Popup.Feedback(_("Testing the NTP server..."), Message.takes_a_while) do
        log.info("Testing reachability of server #{server}")
        ok = reachable_ntp_server?(server)
      end

      if verbosity == :result_popup
        if ok
          # message report - result of test of connection to NTP server
          Popup.Notify(_("Server is reachable and responds properly."))
        else
          # error message  - result of test of connection to NTP server
          # report error instead of simple message (#306018)
          Report.Error(_("Server is unreachable or does not respond properly."))
        end
      end
      ok
    end

    # Detect NTP servers present in the local network
    # @param [Symbol] method symbol method of the detection (only `slp suported ATM)
    # @return a list of found NTP servers
    def DetectNtpServers(method)
      if method == :slp
        required_package = "yast2-slp"

        # if package is not installed (in the inst-sys, it is: bnc#399659)
        if !Stage.initial && !PackageSystem.Installed(required_package)
          if !PackageSystem.CheckAndInstallPackages([required_package])
            Report.Error(
              Builtins.sformat(
                _(
                  "Cannot search for NTP server in local network\nwithout package %1 installed.\n"
                ),
                required_package
              )
            )
            Builtins.y2warning("Not searching for local NTP servers via SLP")
            return []
          else
            SCR.RegisterAgent(path(".slp"), term(:ag_slp, term(:SlpAgent)))
          end
        end

        servers = SLPAPI.FindSrvs("service:ntp", "")
        server_names = Builtins.maplist(servers) do |m|
          Ops.get_string(m, "pcHost", "")
        end
        server_names = Builtins.filter(server_names) { |s| s != "" }
        return deep_copy(server_names)
      end
      Builtins.y2error("Unknown detection method: %1", method)
      []
    end

    # Return required packages for auto-installation
    # @return [Hash] of packages to be installed and to be removed
    def AutoPackages
      { "install" => @required_packages, "remove" => [] }
    end

    # Convenience method to obtain the list of ntp servers proposed by DHCP
    # @see https://www.rubydoc.info/github/yast/yast-network/Yast/LanClass:${0}
    def dhcp_ntp_servers
      Yast::Lan.dhcp_ntp_servers
    end

    publish variable: :AbortFunction, type: "boolean ()"
    publish variable: :modified, type: "boolean"
    publish variable: :write_only, type: "boolean"
    publish variable: :run_service, type: "boolean"
    publish variable: :synchronize_time, type: "boolean"
    publish variable: :sync_interval, type: "integer"
    publish variable: :service_name, type: "string"
    publish variable: :ntp_policy, type: "string"
    publish variable: :ntp_selected, type: "boolean"
    publish variable: :ad_controller, type: "string"
    publish variable: :config_has_been_read, type: "boolean"
    publish function: :GetNtpServers, type: "map <string, map <string, string>> ()"
    publish function: :GetCountryNames, type: "map <string, string> ()"
    publish function: :GetNtpServersByCountry, type: "list (string, boolean)"
    publish function: :ProcessNtpConf, type: "boolean ()"
    publish function: :ReadSynchronization, type: "boolean ()"
    publish function: :Read, type: "boolean ()"
    publish function: :GetUsedNtpServers, type: "list <string> ()"
    publish variable: :random_pool_servers, type: "list <string>"
    publish function: :Write, type: "boolean ()"
    publish function: :Import, type: "boolean (map)"
    publish function: :Export, type: "map ()"
    publish function: :Summary, type: "string ()"
    publish function: :TestNtpServer, type: "boolean (string, symbol)"
    publish function: :DetectNtpServers, type: "list <string> (symbol)"
    publish function: :AutoPackages, type: "map ()"

  private

    # Reads and returns all known countries with their country codes
    #
    # @return [Hash{String => String}] of known contries
    #
    # **Structure:**
    #
    #     $[
    #        "CL" : "Chile",
    #        "FR" : "France",
    #        ...
    #      ]
    def GetAllKnownCountries
      # first point of dependence on yast2-country-data
      if !@countries_already_read
        @known_countries = Convert.convert(
          Builtins.eval(
            SCR.Read(
              path(".target.ycp"),
              Directory.find_data_file("country.ycp")
            )
          ),
          from: "any",
          to:   "map <string, string>"
        )
        @countries_already_read = true
        @known_countries = {} if @known_countries.nil?
      end

      # workaround bug #241054: servers in United Kingdom are in domain .uk
      # domain .gb does not exist - add UK to the list of known countries
      if Builtins.haskey(@known_countries, "GB")
        Ops.set(@known_countries, "UK", Ops.get(@known_countries, "GB", ""))
        @known_countries = Builtins.remove(@known_countries, "GB")
      end

      deep_copy(@known_countries)
    end

    # Set @ntp_policy according to NETCONFIG_NTP_POLICY value found in
    # /etc/sysconfig/network/config or with {DEFAULT_NTP_POLICY} if not found
    #
    # @return [String] read value or {DEFAULT_NTP_POLICY} as default
    def read_policy!
      # SCR::Read may return nil (no such value in sysconfig, file not there etc. )
      # set if not nil, otherwise use 'auto' as safe fallback (#449362)
      @ntp_policy = SCR.Read(path(".sysconfig.network.config.NETCONFIG_NTP_POLICY")) ||
        DEFAULT_NTP_POLICY
    end

    # Set @ad_controller according to ad_ntp_data["ads"] value found in
    # data_file ad_ntp_data.ycp if exists.
    #
    # Removes the file if some value is read.
    def read_ad_address!
      ad_ntp_file = Directory.find_data_file("ad_ntp_data.ycp")
      if ad_ntp_file
        log.info("Reading #{ad_ntp_file}")
        ad_ntp_data = SCR.Read(path(".target.ycp"), ad_ntp_file)

        @ad_controller = ad_ntp_data["ads"].to_s if ad_ntp_data
        if @ad_controller != ""
          Builtins.y2milestone(
            "Got %1 for ntp sync, deleting %2, since it is no longer needed",
            @ad_controller,
            ad_ntp_file
          )
          SCR.Execute(path(".target.remove"), ad_ntp_file)
        end
      else
        log.info "There is no active directory data's file available."
      end
    end

    # Set @ntp_servers with known servers and known countries pool ntp servers
    def update_ntp_servers!
      @ntp_servers = {}

      read_known_servers.each { |s| cache_server(s) }

      pool_servers_for(GetAllKnownCountries()).each { |p| cache_server(p) }
    end

    # Start a new progress for Read NTP Configuration
    def new_read_progress
      Progress.New(
        _("Initializing NTP Client Configuration"),
        " ",
        2,
        [
          # progress stage
          _("Read network configuration"),
          # progress stage
          _("Read NTP settings")
        ],
        [
          # progress step
          _("Reading network configuration..."),
          # progress step
          _("Reading NTP settings..."),
          # progress step
          _("Finished")
        ],
        ""
      )
    end

    # Start a new progress for Write NTP Configuration
    def new_write_progress
      Progress.New(
        _("Saving NTP Client Configuration"),
        " ",
        2,
        [
          # progress stage
          _("Write NTP settings"),
          # progress stage
          _("Restart NTP daemon")
        ],
        [
          # progress step
          _("Writing the settings..."),
          # progress step
          _("Restarting NTP daemon..."),
          # progress step
          _("Finished")
        ],
        ""
      )
    end

    def update_cfa_record(record)
      cfa_record = record["cfa_record"]
      cfa_record.value = record["address"]
      cfa_record.raw_options = record["options"]
      cfa_record.comment = record["comment"]
    end

    # Write current /etc/chrony.conf
    # @return [Boolean] true on success
    def write_ntp_conf
      begin
        ntp_conf.save
      rescue StandardError => e
        log.error("Failed to write #{NTP_FILE}: #{e.message}")
        return false
      end

      true
    end

    # Writes /etc/sysconfig/network/config NETCONFIG_NTP_POLICY
    # with current @ntp_policy value
    # @return [Boolean] true on success
    def write_policy
      SCR.Write(
        path(".sysconfig.network.config.NETCONFIG_NTP_POLICY"),
        @ntp_policy
      )
      SCR.Write(path(".sysconfig.network.config"), nil)
    end

    # Calls netconfig to update ntp
    # @return [Boolean] true on success
    def update_netconfig
      SCR.Execute(path(".target.bash"), "/sbin/netconfig update -m ntp") == 0
    end

    # Writes sysconfig ntp policy and calls netconfig to update ntp. Report an
    # error if some of the call fails.
    #
    # @return [Boolean] true if write and update success
    def write_and_update_policy
      success = write_policy && update_netconfig

      Report.Error(_("Cannot update the dynamic configuration policy.")) unless success

      success
    end

    # Enable or disable chrony services depending on @run_service value
    # "chrony-wait" service has also to be handled in order to ensure that
    # "chronyd" is working correctly and do not depend on the network status.
    #
    # * When disabling, it also stops the services.
    # * When enabling, it tries to restart the services unless it's in write
    #   only mode.
    def check_service
      # fallbacks to false if not defined
      wait_service_required = ProductFeatures.GetBooleanFeature("globals", "precise_time")
      if @run_service
        # Enable and run services
        if !Service.Enable(@service_name)
          Report.Error(Message.CannotAdjustService(@service_name))
        elsif wait_service_required && !Service.Enable(@wait_service_name)
          Report.Error(Message.CannotAdjustService(@wait_service_name))
        end
        if !@write_only
          if !Service.Restart(@service_name)
            Report.Error(_("Cannot restart \"%s\" service.") % @service_name)
          elsif wait_service_required && !Service.Restart(@wait_service_name)
            Report.Error(_("Cannot restart \"%s\" service.") % @wait_service_name)
          end
        end
      else
        # Disable and stop services
        if !Service.Disable(@service_name)
          Report.Error(Message.CannotAdjustService(@service_name))
        # disable and stop always as wait without chrony does not make sense
        elsif !Service.Disable(@wait_service_name)
          Report.Error(Message.CannotAdjustService(@wait_service_name))
        end
        Service.Stop(@service_name)
        Service.Stop(@wait_service_name)
      end
    end

    # If synchronize time has been enable it writes ntp cron entry for manual
    # sync. If not it removes current cron entry if exists.
    def update_cron_settings
      if @synchronize_time
        SCR.Write(
          path(".target.string"),
          CRON_FILE,
          "-*/#{@sync_interval} * * * * root /usr/sbin/chronyd -q &>/dev/null\n"
        )
      else
        SCR.Execute(
          path(".target.bash"),
          "rm -vf #{CRON_FILE}"
        )
      end
    end

    # Reads from file ntp servers list and return them. Return an empty hash if
    # not able to read the servers.
    #
    # @return [Hash] of ntp servers.
    def read_known_servers
      servers_file = Directory.find_data_file("ntp_servers.yml")

      return {} if !servers_file

      servers = YAML.load_file(servers_file)
      if servers.nil?
        log.error("Failed to read the list of NTP servers")
        return {}
      end

      log.info "Known NTP servers read: #{servers}"

      servers
    end

    # Returns a concatenation of given location and country depending on if
    # them are empty or not.
    #
    # @example
    #   country_server_label("Canary Islands", "Spain") # => " (Canary Islands, Spain)"
    #   country_server_label("Nürnberg", "")            # => " (Nürnberg)"
    #   country_server_label("", "Deutschland")         # => " (Deutschland)"
    #
    # @param [String] location of server
    # @param [String] country of server
    # @return [String] concatenate location and country if not empty
    def country_server_label(location = "", country = "")
      return "" if location.empty? && country.empty?
      return " (#{location}, #{country})" if !location.empty? && !country.empty?

      " (#{location}#{country})"
    end

    # Given a Hash of known countries, it returns a list of pool records for
    # each country.
    # @see #MakePoolRecord
    #
    # @param [Hash <String, String>] known_countries
    # @return [Array <Hash>] pool records for given countries
    def pool_servers_for(known_countries)
      known_countries.map do |short_country, country_name|
        MakePoolRecord(short_country, country_name)
      end
    end

    # Add given server to @ntp_server Hash using the server address as the key
    # and the server as the value
    #
    # @param [Hash <String, String>] server string host name or IP address of the NTP server
    # @return [Boolean] result of the assignation
    def cache_server(server)
      @ntp_servers[server["address"].to_s] = server
    end

    def unsupported_error(unsupported)
      msg = format(
        # TRANSLATORS: error report. %s stands unsupported keys.
        _("Ignoring the NTP configuration. The profile format has changed in an " \
          "incompatible way. These keys are no longer supported: '%s'."),
        unsupported.join("', '")
      )

      displayinfo = Yast::UI.GetDisplayInfo
      width = displayinfo["TextMode"] ? displayinfo.fetch("Width", 80) : 80

      Yast::Report.Error(wrap_text(msg, width - 4))
    end
  end

  NtpClient = NtpClientClass.new
  NtpClient.main
end
