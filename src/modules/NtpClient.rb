# encoding: utf-8

# File:	modules/NtpClient.ycp
# Package:	Configuration of ntp-client
# Summary:	Data for configuration of ntp-client, input and output functions.
# Authors:	Jiri Srain <jsrain@suse.cz>
#
# $Id$
#
# Representation of the configuration of ntp-client.
# Input and output routines.
require "yast"
require "yaml"
require "cfa/ntp_conf"
require "yast2/target_file" # required to cfa work on changed scr

module Yast
  class NtpClientClass < Module
    include Logger

    # the default synchronization interval in minutes when running in the manual
    # sync mode ("Synchronize without Daemon" option, ntp started from cron)
    # Note: the UI field currently uses maximum of 60 minutes
    DEFAULT_SYNC_INTERVAL = 5

    # List of servers defined by the pool.ntp.org to get random ntp servers
    #
    # @see #http://www.pool.ntp.org/
    RANDOM_POOL_NTP_SERVERS = ["0.pool.ntp.org", "1.pool.ntp.org", "2.pool.ntp.org"].freeze

    # Different kinds of records which the server can syncronize with and
    # reference clock record
    #
    # @see http://doc.ntp.org/4.1.0/confopt.htm
    # @see http://doc.ntp.org/4.1.0/clockopt.htm
    SYNC_RECORDS = ["server", "__clock", "peer", "broadcast", "broadcastclient"].freeze

    NTP_FILE = "/etc/ntp.conf".freeze

    def main
      Yast.import "UI"
      textdomain "ntp-client"

      Yast.import "Directory"
      Yast.import "FileUtils"
      Yast.import "Language"
      Yast.import "Message"
      Yast.import "Mode"
      Yast.import "NetworkInterfaces"
      Yast.import "PackageSystem"
      Yast.import "Popup"
      Yast.import "Progress"
      Yast.import "Report"
      Yast.import "Service"
      Yast.import "SLPAPI"
      Yast.import "Stage"
      Yast.import "String"
      Yast.import "Summary"
      Yast.import "SuSEFirewall"
      Yast.import "FileChanges"

      # Abort function
      # return boolean return true if abort
      @AbortFunction = nil

      # Data was modified?
      @modified = false

      # Write only, used during autoinstallation.
      # Don't run services and SuSEconfig, it's all done at one place.
      @write_only = false

      # Read all ntp-client settings
      # @return true on success
      @ntp_records = []

      @restrict_map = {}

      # Should the daemon be started when system boots?
      @run_service = true

      # Should the time synchronized periodicaly?
      @synchronize_time = false

      # The interval of synchronization in minutes.
      @sync_interval = DEFAULT_SYNC_INTERVAL

      # The cron file name for the synchronization.
      @cron_file = "/etc/cron.d/novell.ntp-synchronize"

      # Service name of the NTP daemon
      @service_name = "chronyd"

      # Should the daemon be started in chroot environment?
      @run_chroot = false

      # Netconfig policy: for merging and prioritizing static and DHCP config.
      # FIXME: get a public URL
      # https://svn.suse.de/svn/sysconfig/branches/mt/dhcp6-netconfig/netconfig/doc/README
      @ntp_policy = "auto"

      # Index of the currently sellected item
      @selected_index = -1

      # The currently sellected item
      @selected_record = {}

      # Active Directory controller
      @ad_controller = ""

      # Should the firewall settings be changed?
      @change_firewall = false

      # Required packages
      @required_packages = ["chrony"]

      # ports in firewall to open
      @firewall_services = ["service:ntp"]

      # List of known NTP servers
      # server address -> information
      #  address: the key repeated
      #  country: CC (uppercase)
      #  location: for displaying
      #  ...: (others are unused)
      @ntp_servers = nil

      # Mapping between country codes and country names ("CZ" -> "Czech Republic")
      @country_names = nil

      @simple_dialog = false

      @config_has_been_read = false

      @ntp_selected = false

      # for lazy loading
      @countries_already_read = false
      @known_countries = {}

      @random_pool_servers = RANDOM_POOL_NTP_SERVERS

      @deleted_records = []
    end

    def add_to_deleted_records(records)
      records.each do |record|
        cfa = record["cfa_record"]
        cfa_fudge = record["cfa_fudge_record"]
        @deleted_records << cfa if cfa
        @deleted_records << cfa_fudge if cfa_fudge
      end
    end

    def PolicyIsAuto
      @ntp_policy == "auto" || @ntp_policy == "STATIC *"
    end

    def PolicyIsNomodify
      @ntp_policy == ""
    end

    def PolicyIsNonstatic
      @ntp_policy != "" && @ntp_policy != "STATIC"
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

    # Read current language (RC_LANG from sysconfig)
    # @return two-letter language code (cs_CZ.UTF-8 -> CZ)
    def GetCurrentLanguageCode
      lang = Convert.to_string(SCR.Read(path(".sysconfig.language.RC_LANG")))

      # second point of dependence on yast2-country-data
      Language.GetGivenLanguageCountry(lang)
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

    # Get the mapping between country codea and names ("CZ" -> "Czech Republic")
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

      load_ntp_records

      log.info("Raw ntp conf #{ntp_conf.raw}")
      true
    end

    def load_ntp_records
      @ntp_records = ntp_conf.records.map do |record|
        {
          "type"       => record.type,
          "address"    => record.value,
          "options"    => record.raw_options,
          "comment"    => record.comment.to_s,
          "cfa_record" => record
        }
      end
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

      fudge_records = Builtins.filter(@ntp_records) do |m|
        Ops.get_string(m, "type", "") == "fudge"
      end

      fudge_map = Convert.convert(
        Builtins.listmap(fudge_records) do |m|
          key = Ops.get_string(m, "address", "")
          { key => m }
        end,
        from: "map <string, map>",
        to:   "map <string, map <string, any>>"
      )

      restrict_records = Builtins.filter(@ntp_records) do |m|
        Ops.get_string(m, "type", "") == "restrict"
      end

      @restrict_map = Convert.convert(
        Builtins.listmap(restrict_records) do |m|
          key = Ops.get_string(m, "address", "")
          value2 = {}
          opts = Builtins.splitstring(
            String.CutBlanks(Ops.get_string(m, "options", "")),
            " \t"
          )
          if Ops.get(opts, 0, "") == "mask"
            Ops.set(value2, "mask", Ops.get(opts, 1, ""))
            Ops.set(opts, 0, "")
            Ops.set(opts, 1, "")
          else
            Ops.set(value2, "mask", "")
          end
          Ops.set(
            value2,
            "options",
            String.CutBlanks(Builtins.mergestring(opts, " "))
          )
          Ops.set(value2, "comment", Ops.get_string(m, "comment", ""))
          value2["cfa_record"] = m["cfa_record"]
          { key => value2 }
        end,
        from: "map <string, map>",
        to:   "map <string, map <string, any>>"
      )

      @ntp_records = Builtins.filter(@ntp_records) do |m|
        Ops.get_string(m, "type", "") != "fudge"
      end

      @ntp_records = Builtins.filter(@ntp_records) do |m|
        Ops.get_string(m, "type", "") != "restrict"
      end

      @ntp_records = Convert.convert(
        Builtins.maplist(@ntp_records) do |m|
          if Builtins.haskey(fudge_map, Ops.get_string(m, "address", ""))
            Ops.set(
              m,
              "fudge_options",
              Ops.get_string(
                fudge_map,
                [Ops.get_string(m, "address", ""), "options"],
                ""
              )
            )
            Ops.set(
              m,
              "fudge_comment",
              Ops.get_string(
                fudge_map,
                [Ops.get_string(m, "address", ""), "comment"],
                ""
              )
            )
            m["cfa_fudge_record"] = ntp_conf.records.find do |record|
              record.type == "fudge" && record.value == m["address"]
            end
          end
          m
        end,
        from: "list <map>",
        to:   "list <map <string, any>>"
      )

      # mark local clock to be local clock and not real servers
      @ntp_records = Builtins.maplist(@ntp_records) do |p|
        if Ops.get_string(p, "type", "") == "server" &&
            Builtins.regexpmatch(
              Ops.get_string(p, "address", ""),
              "^127.127.[0-9]+.[0-9]+$"
            )
          Ops.set(p, "type", "__clock")
        end
        p
      end

      true
    end

    # Read the synchronization status, fill
    # synchronize_time and sync_interval variables
    # Return updated value of synchronize_time
    def ReadSynchronization
      crontab = SCR.Read(path(".cron"), @cron_file, "")
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

      sl = 500

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

      # Stay away if the user may have made changes which we cannot parse.
      # But bnc#456553, no pop-ups for CLI.
      failed = !Mode.commandline && !FileChanges.CheckFiles(["/etc/ntp.conf"])

      ProcessNtpConf()
      ReadSynchronization()

      failed = true unless read_chroot_config!

      if failed
        # While calling "yast clone_system" it is possible that
        # the ntp server has not already been installed at that time.
        # (This would be done if yast2-ntp-client will be called in the UI)
        # In that case the error popup will not be shown. (bnc#889557)
        Report.Error(Message.CannotReadCurrentSettings) unless Mode.config
      end

      progress_orig2 = Progress.set(false)
      SuSEFirewall.Read
      Progress.set(progress_orig2)

      return false if !go_next
      Progress.Title(_("Finished")) if progress?

      Builtins.sleep(sl)

      return false if Abort()
      @modified = false
      true
    end

    # Function returns list of NTP servers used in the configuration.
    #
    # @return [Array<String>] of servers
    def GetUsedNtpServers
      used_servers = []
      @ntp_records.each do |record|
        used_servers << record["address"] if record["type"] == "server"
      end

      used_servers
    end

    # Checks whether all servers listed in the random_pool_servers list
    # are used in the configuration.
    #
    # @return [Boolean] true if enabled
    def IsRandomServersServiceEnabled
      used_servers = GetUsedNtpServers()

      RANDOM_POOL_NTP_SERVERS.all? { |s| used_servers.include? s }
    end

    # Removes all servers contained in the random_pool_servers list
    # from the current configuration.
    def DeActivateRandomPoolServersFunction
      deleted_records, @ntp_records = @ntp_records.partition do |record|
        record["type"] == "server" && RANDOM_POOL_NTP_SERVERS.include?(record["address"])
      end
      add_to_deleted_records(deleted_records)

      nil
    end

    # Add servers needed for random_pool_servers function
    # into the current configuration.
    def ActivateRandomPoolServersFunction
      # leave the current configuration if any
      store_current_options = {}
      Builtins.foreach(@ntp_records) do |one_record|
        if Ops.get_string(one_record, "type", "") == "server" &&
            Ops.get_string(one_record, "address", "") != ""
          one_address = Ops.get_string(one_record, "address", "")
          Ops.set(store_current_options, one_address, {})
          Ops.set(
            store_current_options,
            [one_address, "options"],
            Ops.get_string(one_record, "options", "")
          )
        end
      end

      # remove all old ones
      DeActivateRandomPoolServersFunction()

      deleted_records, @ntp_records = @ntp_records.partition do |record|
        record["type"] == "server"
      end
      add_to_deleted_records(deleted_records)

      Builtins.foreach(@random_pool_servers) do |one_server|
        one_options = ""
        if Builtins.haskey(store_current_options, one_server)
          one_options = Ops.get_string(
            store_current_options,
            [one_server, "options"],
            ""
          )
          Builtins.y2milestone(
            "Leaving current configuration for server '%1', options '%2'",
            one_server,
            one_options
          )
        end
        @ntp_records <<
          {
            "address" => one_server,
            "comment" => "# Random pool server, see http://www.pool.ntp.org/ " \
                         "for more information",
            "options" => one_options,
            "type"    => "server"
          }
      end

      nil
    end

    # Write all ntp-client settings
    # @return true on success
    def Write
      # We do not set help text here, because it was set outside
      new_write_progress if progress?

      # write settings
      return false if !go_next

      # Restrict map records are written first to not mangle the config file
      # (bsc#983486)
      @ntp_records = restrict_map_records + @ntp_records

      log.info "Writing settings #{@ntp_records}"

      Report.Error(Message.CannotWriteSettingsTo("/etc/ntp.conf")) if !write_ntp_conf

      write_and_update_policy

      write_chroot_config

      # restart daemon
      return false if !go_next

      # SuSEFirewall::Write checks on its own whether there are pending
      # changes, so call it always. bnc#476951

      progress_orig = Progress.set(false)
      SuSEFirewall.Write
      Progress.set(progress_orig)

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
      settings = deep_copy(settings)
      @synchronize_time = Ops.get_boolean(settings, "synchronize_time", false)
      @sync_interval = Ops.get_integer(settings, "sync_interval", DEFAULT_SYNC_INTERVAL)
      @run_service = Ops.get_boolean(settings, "start_at_boot", false)
      @run_chroot = Ops.get_boolean(settings, "start_in_chroot", true)
      # compatibility: configure_dhcp:true translates to ntp_policy:auto
      config_dhcp = Ops.get_boolean(settings, "configure_dhcp", false)
      @ntp_policy = Ops.get_string(
        settings,
        "ntp_policy",
        config_dhcp ? "auto" : ""
      )
      @ntp_records = Ops.get_list(settings, "peers", [])
      @ntp_records = Builtins.maplist(@ntp_records) do |p|
        if Builtins.haskey(p, "key") && Builtins.haskey(p, "value")
          Ops.set(p, "type", Ops.get_string(p, "key", ""))
          Ops.set(p, "address", Ops.get_string(p, "value", ""))
          if Builtins.haskey(p, "param")
            Ops.set(p, "options", Ops.get_string(p, "param", ""))
          end
        end
        next deep_copy(p)
      end

      # sanitize records
      @ntp_records = @ntp_records.map { |r| sanitize_record(r) }

      # restricts is a list of entries whereas restrict_map
      # is a map with target key (ip, ipv4-tag, ipv6-tag,...).
      restricts = settings["restricts"] || []
      @restrict_map = {}
      restricts.each do |entry|
        target = entry.delete("target").strip
        @restrict_map[target] = sanitize_record(entry)
      end
      @modified = true
      true
    end

    # Dump the ntp-client settings to a single map
    # (For use by autoinstallation.)
    # @return [Hash] Dumped settings (later acceptable by Import ())
    def Export
      # restrict_map is a map with the key ip,ipv4-tag or ipv6-tag.
      # This will be converted into a list in order to use it in
      # autoyast XML file properly.

      restricts = @restrict_map.collect do |target, values|
        # cfa_record not needed for export
        export_values = values.dup
        export_values.delete("cfa_record")
        export_values["target"] = target
        export_values
      end

      peers = @ntp_records.dup
      peers.each do |peer|
        peer.delete("cfa_record")
        peer.delete("cfa_fudge_record")
      end

      {
        "synchronize_time" => @synchronize_time,
        "sync_interval"    => @sync_interval,
        "start_at_boot"    => @run_service,
        "start_in_chroot"  => @run_chroot,
        "ntp_policy"       => @ntp_policy,
        "peers"            => peers,
        "restricts"        => restricts
      }
    end

    # Create a textual summary and a list of unconfigured cards
    # @return [String] summary of the current configuration
    def Summary
      summary = ""
      if @run_service
        # summary string
        summary = Summary.AddLine(
          summary,
          _("The NTP daemon starts when starting the system.")
        )
      else
        # summary string
        summary = Summary.AddLine(
          summary,
          _("The NTP daemon does not start automatically.")
        )
      end

      types = {
        # summary string, %1 is list of addresses
        "server"          => _(
          "Servers: %1"
        ),
        # summary string, %1 is list of addresses
        "__clock"         => _(
          "Radio Clocks: %1"
        ),
        # summary string, %1 is list of addresses
        "peer"            => _(
          "Peers: %1"
        ),
        # summary string, %1 is list of addresses
        "broadcast"       => _(
          "Broadcast time information to: %1"
        ),
        # summary string, %1 is list of addresses
        "broadcastclient" => _(
          "Accept broadcasted time information from: %1"
        )
      }
      #   if (config_dhcp)
      #   {
      #   summary = Summary::AddLine (summary,
      #   // summary string
      #   _("Configure NTP daemon via DHCP."));
      #   return summary;
      #   }
      # netconfig policy
      if PolicyIsAuto()
        # summary string, FIXME
        summary = Summary.AddLine(
          summary,
          _("Combine static and DHCP configuration.")
        )
      elsif PolicyIsNomodify()
        # summary string, FIXME
        summary = Summary.AddLine(summary, _("Static configuration only."))
      else
        # summary string, FIXME: too generic!
        summary = Summary.AddLine(summary, _("Custom configuration policy."))
      end

      SYNC_RECORDS.each do |t|
        type_records = @ntp_records.select { |r| r["type"] == t }
        names = type_records.map { |r| r["address"].to_s }.select { |n| n != "" }
        summary = Summary.AddLine(summary, "#{types[t]}#{names.join(", ")}") if !names.empty?
      end

      summary
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
    # @param [Fixnum] integer ip version to use (4 or 6)
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

    # Get the list of synchronization-related records
    # @return a list of maps with keys type (eg. "server"), address and index.
    def getSyncRecords
      index = -1
      @ntp_records.each_with_object([]) do |record, ret|
        index += 1
        type = record["type"]
        next if !sync_record?(type)
        ret << {
          "type"    => type,
          "index"   => index,
          "address" => record["address"].to_s,
          "device"  => record["device"].to_s
        }
      end
    end

    # Select synchronization record
    # @param [Fixnum] index integer, -1 for creating a new record
    # @return [Boolean] true on success
    def selectSyncRecord(index)
      ret = true
      unless (-1..@ntp_records.size - 1).cover?(index)
        log.error("Record with index #{index} doesn't exist, creating new")
        index = -1
        ret = false
      end
      @selected_record = index == -1 ? {} : @ntp_records[index]
      @selected_index = index
      ret
    end

    # Find index of synchronization record
    # @param [String] type string record type
    # @param [String] address string address
    # @return [Fixnum] index of the record if found, -1 otherwise
    def findSyncRecord(type, address)
      index = -1
      ret = -1
      Builtins.foreach(@ntp_records) do |m|
        index = Ops.add(index, 1)
        if type == Ops.get_string(m, "type", "") &&
            address == Ops.get_string(m, "address", "")
          ret = index
        end
      end
      ret
    end

    # Store currently sellected synchronization record
    # @return [Boolean] true on success
    def storeSyncRecord
      if @selected_index == -1
        @ntp_records = Builtins.add(@ntp_records, @selected_record)
      else
        Ops.set(@ntp_records, @selected_index, @selected_record)
      end
      @modified = true
      true
    end

    # Delete specified synchronization record
    # @param [Fixnum] index integer index of record to delete
    # @return [Boolean] true on success
    def deleteSyncRecord(index)
      unless (0..@ntp_records.size - 1).cover?(index)
        log.error("Record with index #{index} doesn't exist")
        return false
      end
      add_to_deleted_records([@ntp_records[index]])
      @ntp_records.delete_at(index)
      @modified = true
    end

    # Ensure that selected_record["options"] contains the option.
    # (A set operation in a string)
    def enableOptionInSyncRecord(option)
      # careful, "burst" != "iburst"
      old = Ops.get_string(@selected_record, "options", "")
      old_l = Builtins.splitstring(old, " \t")
      old_l = Builtins.add(old_l, option) if !Builtins.contains(old_l, option)
      Ops.set(@selected_record, "options", Builtins.mergestring(old_l, " "))

      nil
    end

    # Return required packages for auto-installation
    # @return [Hash] of packages to be installed and to be removed
    def AutoPackages
      { "install" => @required_packages, "remove" => [] }
    end

  private

    # Remove blank spaces in values
    #
    # @note to avoid augeas parsing errors, comments should be sanitized by
    #   removing blank spaces at the beginning and adding line break.
    def sanitize_record(record)
      sanitized = record.dup
      sanitized.each do |key, value|
        if key.include?("comment")
          value.sub!(/^ */, "")
          value << "\n" unless value.include?("\n")
        elsif value.respond_to?(:strip!)
          value.strip!
        end
      end
      sanitized
    end

    # Set @ntp_policy according to NETCONFIG_NTP_POLICY value found in
    # /etc/sysconfig/network/config or with "auto" if not found
    #
    # @return [String] read value or "auto" as default
    def read_policy!
      # SCR::Read may return nil (no such value in sysconfig, file not there etc. )
      # set if not nil, otherwise use 'auto' as safe fallback (#449362)
      @ntp_policy = SCR.Read(path(".sysconfig.network.config.NETCONFIG_NTP_POLICY")) || "auto"
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

    # Set @run_chroot according to NTPD_RUN_CHROOTED value found in
    # /etc/sysconfig/ntp
    #
    # @return [Boolean] true when value is "yes"; false in any other case.
    def read_chroot_config!
      run_chroot_s = SCR.Read(path(".sysconfig.ntp.NTPD_RUN_CHROOTED"))

      @run_chroot = run_chroot_s == "yes"

      log.error("Failed reading .sysconfig.ntp.NTPD_RUN_CHROOTED") if run_chroot_s.nil?

      run_chroot_s.nil? ? false : true
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

    # Write current /etc/ntp.conf with @ntp_records
    # @return [Boolean] true on success
    def write_ntp_conf
      records_for_write.each do |record|
        unless record["cfa_record"]
          ntp_conf.records << CFA::NtpConf::Record.record_class(record["type"]).new
          record["cfa_record"] = ntp_conf.records.last
        end

        update_cfa_record(record)
        log.info "new record #{record.inspect}"
      end

      ntp_conf.records.delete_if { |record| @deleted_records.include?(record) }

      begin
        ntp_conf.save
      rescue StandardError => e
        log.error("Failed to write #{NTP_FILE}: #{e.message}")
        return false
      end

      FileChanges.StoreFileCheckSum(NTP_FILE)

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

    # Writes /etc/sysconfig/ntp NTPD_RUN_CHROOTED with "yes" if current
    # @run_chroot is true or with "no" in other case
    #
    # @return [Boolean] true on success
    def write_chroot_config
      SCR.Write(
        path(".sysconfig.ntp.NTPD_RUN_CHROOTED"),
        @run_chroot ? "yes" : "no"
      )

      SCR.Write(path(".sysconfig.ntp"), nil)
    end

    # Enable or disable ntp service depending on @run_service value
    #
    # * When disabling, it also stops the service.
    # * When enabling, it tries to restart the service unless it's in write
    #   only mode.
    def check_service
      adjusted = @run_service ? Service.Enable(@service_name) : Service.Disable(@service_name)

      # error report
      Report.Error(Message.CannotAdjustService("NTP")) unless adjusted

      if @run_service
        unless @write_only
          # error report
          Report.Error(_("Cannot restart the NTP daemon.")) unless Service.Restart(@service_name)
        end
      else
        Service.Stop(@service_name)
      end
    end

    # If synchronize time has been enable it writes ntp cron entry for manual
    # sync. If not it removes current cron entry if exists.
    def update_cron_settings
      if @synchronize_time
        SCR.Write(
          path(".target.string"),
          @cron_file,
          "-*/#{@sync_interval} * * * * root /usr/sbin/chronyd -q &>/dev/null\n"
        )
      else
        SCR.Execute(
          path(".target.bash"),
          "test -e #{@cron_file} && rm #{@cron_file};"
        )
      end
    end

    def record_for_write(record)
      {
        "type"       => record["type"] == "__clock" ? "server" : record["type"],
        "address"    => record["address"],
        "options"    => record["options"].to_s.strip,
        "comment"    => record["comment"].to_s,
        "cfa_record" => record["cfa_record"]
      }
    end

    # Parse fudge options of given record and returns a new fudge record for
    # write
    def fudge_options_for_write(record)
      {
        "type"       => "fudge",
        "address"    => record["address"],
        "options"    => record["fudge_options"].to_s.strip,
        "comment"    => record["fudge_comment"].to_s,
        "cfa_record" => record["cfa_fudge_record"]
      }
    end

    # Returns current restrict map as a list of ntp records
    def restrict_map_records
      @restrict_map.map do |key, m|
        address = key
        options = m["options"].to_s.split

        if ["-4", "-6"].include?(key)
          address = options.first
          options.shift
          options.unshift("ipv4") if key == "-4"
          options.unshift("ipv6") if key == "-6"
        end

        options << "mask #{m["mask"]}" if !m["mask"].to_s.empty?

        {
          "type"       => "restrict",
          "address"    => address,
          "comment"    => m["comment"].to_s,
          "options"    => options.join(" "),
          "cfa_record" => m["cfa_record"]
        }
      end
    end

    # Prepare current ntp_records in hashes for write, splitting fudge options
    # of __clock records in their own hashes.
    def records_for_write
      @ntp_records.each_with_object([]) do |record, ret|
        ret << record_for_write(record)
        ret << fudge_options_for_write(record) if record["type"] == "__clock"
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
    # @param [String] server location
    # @param [String] server country
    # @return [String] concatenate location and country if not empty
    def country_server_label(location = "", country = "")
      return "" if location.empty? && country.empty?
      return " (#{location}, #{country})" if !location.empty? && !country.empty?

      " (#{location}#{country})"
    end

    # @see SYNC_RECORDS
    def sync_record?(record_type)
      SYNC_RECORDS.include? record_type
    end

    # Given a Hash of known countries, it returns a list of pool records for
    # each country.
    # @see #MakePoolRecord
    #
    # @param [Hash <String, String>] known countries
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

    # CFA instance for reading/writing /etc/ntp.conf
    def ntp_conf
      @ntp_conf ||= CFA::NtpConf.new
    end

    publish variable: :AbortFunction, type: "boolean ()"
    publish variable: :modified, type: "boolean"
    publish variable: :write_only, type: "boolean"
    publish variable: :ntp_records, type: "list <map <string, any>>"
    publish variable: :restrict_map, type: "map <string, map <string, any>>"
    publish variable: :run_service, type: "boolean"
    publish variable: :synchronize_time, type: "boolean"
    publish variable: :sync_interval, type: "integer"
    publish variable: :cron_file, type: "string"
    publish variable: :service_name, type: "string"
    publish variable: :run_chroot, type: "boolean"
    publish variable: :ntp_policy, type: "string"
    publish variable: :selected_index, type: "integer"
    publish variable: :selected_record, type: "map <string, any>"
    publish variable: :ad_controller, type: "string"
    publish variable: :change_firewall, type: "boolean"
    publish variable: :required_packages, type: "list"
    publish variable: :firewall_services, type: "list <string>"
    publish variable: :simple_dialog, type: "boolean"
    publish variable: :config_has_been_read, type: "boolean"
    publish variable: :ntp_selected, type: "boolean"
    publish function: :PolicyIsAuto, type: "boolean ()"
    publish function: :PolicyIsNomodify, type: "boolean ()"
    publish function: :PolicyIsNonstatic, type: "boolean ()"
    publish function: :GetAllKnownCountries, type: "map <string, string> ()"
    publish function: :GetCurrentLanguageCode, type: "string ()"
    publish function: :GetNtpServers, type: "map <string, map <string, string>> ()"
    publish function: :GetCountryNames, type: "map <string, string> ()"
    publish function: :GetNtpServersByCountry, type: "list (string, boolean)"
    publish function: :ProcessNtpConf, type: "boolean ()"
    publish function: :ReadSynchronization, type: "boolean ()"
    publish function: :Read, type: "boolean ()"
    publish function: :GetUsedNtpServers, type: "list <string> ()"
    publish variable: :random_pool_servers, type: "list <string>"
    publish function: :IsRandomServersServiceEnabled, type: "boolean ()"
    publish function: :DeActivateRandomPoolServersFunction, type: "void ()"
    publish function: :ActivateRandomPoolServersFunction, type: "void ()"
    publish function: :Write, type: "boolean ()"
    publish function: :Import, type: "boolean (map)"
    publish function: :Export, type: "map ()"
    publish function: :Summary, type: "string ()"
    publish function: :TestNtpServer, type: "boolean (string, symbol)"
    publish function: :DetectNtpServers, type: "list <string> (symbol)"
    publish function: :getSyncRecords, type: "list <map <string, any>> ()"
    publish function: :selectSyncRecord, type: "boolean (integer)"
    publish function: :findSyncRecord, type: "integer (string, string)"
    publish function: :storeSyncRecord, type: "boolean ()"
    publish function: :deleteSyncRecord, type: "boolean (integer)"
    publish function: :enableOptionInSyncRecord, type: "void (string)"
    publish function: :AutoPackages, type: "map ()"
  end

  NtpClient = NtpClientClass.new
  NtpClient.main
end
