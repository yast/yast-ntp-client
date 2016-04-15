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

module Yast
  class NtpClientClass < Module
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
      @sync_interval = 5

      # The cron file name for the synchronization.
      @cron_file = "/etc/cron.d/novell.ntp-synchronize"

      # Service name of the NTP daemon
      @service_name = "ntpd"

      # Should the daemon be started in chroot environment?
      @run_chroot = false


      # Netconfig policy: for merging and prioritizing static and DHCP config.
      # FIXME get a public URL
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
      @required_packages = ["ntp"]

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

      # List of servers defined by the pool.ntp.org to get random ntp servers
      #
      # @see #http://www.pool.ntp.org/
      @random_pool_servers = [
        "0.pool.ntp.org",
        "1.pool.ntp.org",
        "2.pool.ntp.org"
      ]
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
      return @AbortFunction.call == true if @AbortFunction != nil
      false
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
      #first point of dependence on yast2-country-data
      if !@countries_already_read
        @known_countries = Convert.convert(
          Builtins.eval(
            SCR.Read(
              path(".target.ycp"),
              Ops.add(Directory.datadir, "/country.ycp")
            )
          ),
          :from => "any",
          :to   => "map <string, string>"
        )
        @countries_already_read = true
        @known_countries = {} if @known_countries == nil
      end

      #workaround bug #241054: servers in United Kingdom are in domain .uk
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

      #second point of dependence on yast2-country-data
      Language.GetGivenLanguageCountry(lang)
    end

    def MakePoolRecord(_CC, location)
      mycc = Builtins.tolower(_CC)
      #There is no gb.pool.ntp.org only uk.pool.ntp.org
      mycc = "uk" if mycc == "gb"
      {
        "address"  => Ops.add(mycc, ".pool.ntp.org"),
        "country"  => _CC,
        "location" => location
      }
    end

    # Get the list of known NTP servers
    # @return a list of known NTP servers
    def GetNtpServers
      if @ntp_servers == nil
        @ntp_servers = {}
        #FIXME This is wrong approach, because datadir should be array of all Y2DIR/DATA
        # so we need to skip it in tests, even if we set Y2DIR properly
        return {} if Mode.test
        servers = YAML.load_file(Directory.datadir + "/ntp_servers.yml") rescue nil
        if servers == nil 
          Builtins.y2error("Failed to read the list of NTP servers")
        else
          Builtins.y2milestone(
            "%1 known NTP servers read",
            Builtins.size(servers)
          )
          @ntp_servers = Builtins.listmap(servers) do |s|
            server = Ops.get(s, "address", "")
            { server => s }
          end
        end
        Builtins.foreach(GetAllKnownCountries()) do |short_country, country_name|
          # just refactored existing code
          p = MakePoolRecord(short_country, country_name)
          Ops.set(@ntp_servers, Ops.get(p, "address", ""), p)
        end
      end

      deep_copy(@ntp_servers)
    end

    # Get the mapping between country codea and names ("CZ" -> "Czech Republic")
    # @return a map the country codes and names mapping
    def GetCountryNames
      if @country_names == nil
        @country_names = Convert.convert(
          Builtins.eval(SCR.Read(path(".target.yast2"), "country.ycp")),
          :from => "any",
          :to   => "map <string, string>"
        )
      end
      if @country_names == nil
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
      if country != ""
        servers = Builtins.filter(servers) do |s, o|
          Ops.get(o, "country", "") == country
        end
        # bnc#458917 add country, in case data/country.ycp does not have it
        p = MakePoolRecord(country, "")
        Ops.set(servers, Ops.get(p, "address", ""), p)
      else
        country_names = GetCountryNames()
      end

      default_already_chosen = false
      items = Builtins.maplist(servers) do |s, o|
        label = Ops.get(o, "location", "")
        l_country = Ops.get(o, "country", "")
        if country != ""
          l_country = ""
        else
          l_country = Ops.get(country_names, l_country, l_country)
        end
        if label != "" && l_country != ""
          label = Builtins.sformat("%1 (%2, %3)", s, label, l_country)
        elsif label == "" && l_country == ""
          label = s
        else
          label = Builtins.sformat("%1 (%2%3)", s, label, l_country)
        end

        # Select the first occurrence of pool.ntp.org as the default option (bnc#940881)
        if default_already_chosen
          selected = false
        else
          selected = default_already_chosen = s.end_with?("pool.ntp.org")
        end

        if terse_output
          next Item(Id(s), s, selected)
        else
          next Item(Id(s), label, selected)
        end
      end

      deep_copy(items)
    end

    # Read and parse /etc.ntp.conf
    # @return true on success
    def ProcessNtpConf
      if @config_has_been_read
        Builtins.y2milestone("Configuration has been read already, skipping.")
        return false
      end

      conf = nil
      if FileUtils.Exists("/etc/ntp.conf")
        conf = Convert.to_map(SCR.Read(path(".etc.ntp_conf.all")))
      end

      if conf == nil
        Builtins.y2error(
          "Failed to read /etc/ntp.conf, either it doesn't exist or contains no data"
        )
        return false
      end
      Builtins.y2milestone("Raw ntp conf %1", conf)
      @config_has_been_read = true
      value = Ops.get_list(conf, "value", [])
      index = -1
      @ntp_records = Builtins.maplist(value) do |m|
        index = Ops.add(index, 1)
        type = Ops.get_string(m, "name", "")
        address = Ops.get_string(m, "value", "")
        options = ""
        if Builtins.contains(
            [
              "server",
              "peer",
              "broadcast",
              "broadcastclient",
              "manycast",
              "manycastclient",
              "fudge",
              "restrict"
            ],
            type
          )
          l = Builtins.splitstring(address, " \t")
          l = Builtins.filter(l) { |s| s != "" }
          address = Ops.get(l, 0, "")
          Ops.set(l, 0, "")
          options = Builtins.mergestring(l, " ")
        end
        entry = {
          "type"    => type,
          "address" => address,
          "options" => options,
          "comment" => Ops.get_string(m, "comment", "")
        }
        deep_copy(entry)
      end
      fudge_records = Builtins.filter(@ntp_records) do |m|
        Ops.get_string(m, "type", "") == "fudge"
      end
      fudge_map = Convert.convert(
        Builtins.listmap(fudge_records) do |m|
          key = Ops.get_string(m, "address", "")
          { key => m }
        end,
        :from => "map <string, map>",
        :to   => "map <string, map <string, any>>"
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
          { key => value2 }
        end,
        :from => "map <string, map>",
        :to   => "map <string, map <string, any>>"
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
          end
          deep_copy(m)
        end,
        :from => "list <map>",
        :to   => "list <map <string, any>>"
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
        deep_copy(p)
      end

      true
    end

    # Read the synchronization status, fill
    # synchronize_time and sync_interval variables
    # Return updated value of synchronize_time
    def ReadSynchronization
      crontab = Convert.to_list(SCR.Read(path(".cron"), @cron_file, ""))
      Builtins.y2milestone("CRONTAB %1", crontab)
      tmp = Ops.get_string(crontab, [0, "events", 0, "active"], "0")
      @synchronize_time = tmp == "1"
      tmp = Ops.get_string(crontab, [0, "events", 0, "minute"], "*/5")
      Builtins.y2milestone("MINUTE %1", tmp)
      pos = Builtins.regexppos(tmp, "[0-9]+")
      tmp2 = Builtins.substring(
        tmp,
        Ops.get_integer(pos, 0, 0),
        Ops.get_integer(pos, 1, 0)
      )
      @sync_interval = Builtins.tointeger(tmp2)
      Builtins.y2milestone("SYNC_INTERVAL %1", @sync_interval)

      @synchronize_time
    end


    # Read all ntp-client settings
    # @return true on success
    def Read
      return true if @config_has_been_read

      # NtpClient read dialog caption
      caption = _("Initializing NTP Client Configuration")

      steps = 2
      sl = 500

      have_progress = Mode.normal

      # We do not set help text here, because it was set outside
      if have_progress
        Progress.New(
          caption,
          " ",
          steps,
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

      # read network configuration
      return false if Abort()
      Progress.NextStage if have_progress

      progress_orig = Progress.set(false)
      NetworkInterfaces.Read
      Progress.set(progress_orig)

      #SCR::Read may return nil (no such value in sysconfig, file not there etc. )
      policy = Convert.to_string(
        SCR.Read(path(".sysconfig.network.config.NETCONFIG_NTP_POLICY"))
      )
      #set if not nil, otherwise use 'auto' as safe fallback (#449362)
      @ntp_policy = policy if policy != nil

      GetNtpServers()
      GetCountryNames()
      # read current settings
      return false if Abort()
      Progress.NextStage if have_progress

      failed = false

      if !Mode.testsuite && !Mode.installation &&
          !PackageSystem.CheckAndInstallPackagesInteractive(["ntp"])
        Builtins.y2milestone(
          "PackageSystem::CheckAndInstallPackagesInteractive failed"
        )
        return false
      end

      @run_service = Service.Enabled(@service_name)

      #Poke to /var/lib/YaST if there is Active Directory controller address dumped in .ycp file
      ad_ntp_file = Ops.add(Directory.vardir, "/ad_ntp_data.ycp")
      if FileUtils.Exists(ad_ntp_file)
        Builtins.y2milestone("Reading %1", ad_ntp_file)
        ad_ntp_data = Convert.convert(
          SCR.Read(path(".target.ycp"), ad_ntp_file),
          :from => "any",
          :to   => "map <string, string>"
        )
        @ad_controller = Ops.get(ad_ntp_data, "ads", "")
        if @ad_controller != ""
          Builtins.y2milestone(
            "Got %1 for ntp sync, deleting %2, since it is no longer needed",
            @ad_controller,
            ad_ntp_file
          )
          SCR.Execute(path(".target.remove"), ad_ntp_file)
        end
      end

      # Stay away if the user may have made changes which we cannot parse.
      # But bnc#456553, no pop-ups for CLI.
      if !Mode.commandline && !FileChanges.CheckFiles(["/etc/ntp.conf"])
        failed = true
      end
      ProcessNtpConf()

      ReadSynchronization()

      run_chroot_s = Convert.to_string(
        SCR.Read(path(".sysconfig.ntp.NTPD_RUN_CHROOTED"))
      )
      @run_chroot = run_chroot_s == "yes"

      if run_chroot_s == nil
        failed = true
        Builtins.y2error("Failed reading .sysconfig.ntp.NTPD_RUN_CHROOTED")
      end

      if failed
        # While calling "yast clone_system" it is possible that
        # the ntp server has not already been installed at that time.
        # (This would be done if yast2-ntp-client will be called in the UI)
        # In that case the error popup will not be shown. (bnc#889557)
        Report.Error(Message.CannotReadCurrentSettings) unless Mode.config
      end

      if !Mode.testsuite
        progress_orig2 = Progress.set(false)
        SuSEFirewall.Read
        Progress.set(progress_orig2)
      end

      return false if Abort()
      if have_progress
        Progress.NextStage
        Progress.Title(_("Finished"))
      end
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
      Builtins.foreach(@ntp_records) do |record|
        if Ops.get_string(record, "type", "") == "server"
          used_servers = Builtins.add(
            used_servers,
            Ops.get_string(record, "address", "")
          )
        end
      end

      deep_copy(used_servers)
    end

    # Checks whether all servers listed in the random_pool_servers list
    # are used in the configuration.
    #
    # @return [Boolean] true if enabled
    def IsRandomServersServiceEnabled
      # all servers needed by pool.ntp.org service, before checking false == not used
      needed_servers = {}
      Builtins.foreach(@random_pool_servers) do |server_name|
        Ops.set(needed_servers, server_name, false)
      end

      Builtins.foreach(GetUsedNtpServers()) do |used_server|
        # if server is needed by pool.ntp.org and matches
        if Ops.get(needed_servers, used_server) != nil
          Ops.set(needed_servers, used_server, true)
        end
      end

      ret = true
      Builtins.foreach(needed_servers) do |nserver_name, ns_value|
        ret = false if ns_value != true
      end
      ret
    end

    # Removes all servers contained in the random_pool_servers list
    # from the current configuration.
    def DeActivateRandomPoolServersFunction
      Builtins.foreach(@random_pool_servers) do |random_pool_server|
        @ntp_records = Builtins.filter(@ntp_records) do |one_record|
          Ops.get_string(
            # do not filter out not-servers
            one_record,
            "type",
            ""
          ) != "server" ||
            # do not filter out serces that are not random_pool_servers
            Ops.get_string(one_record, "address", "") != random_pool_server
        end
      end

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

      @ntp_records = Builtins.filter(@ntp_records) do |one_record|
        Ops.get_string(
          # filter out all servers
          one_record,
          "type",
          ""
        ) != "server"
      end

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
        @ntp_records = Builtins.add(
          @ntp_records,
          {
            "address" => one_server,
            "comment" => "\n# Random pool server, see http://www.pool.ntp.org/ for more information\n",
            "options" => one_options,
            "type"    => "server"
          }
        )
      end

      nil
    end

    # Write all ntp-client settings
    # @return true on success
    def Write
      #boolean update_dhcp = original_config_dhcp != config_dhcp;

      # NtpClient read dialog caption
      caption = _("Saving NTP Client Configuration")

      steps = 2

      sl = 0
      Builtins.sleep(sl)

      have_progress = Mode.normal

      # We do not set help text here, because it was set outside
      if have_progress
        Progress.New(
          caption,
          " ",
          steps,
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

      # write settings
      return false if Abort()
      Progress.NextStage if have_progress

      if true
        Builtins.foreach(@restrict_map) do |key, m|
          ret = {
            "address" => key,
            "comment" => Ops.get_string(m, "comment", ""),
            "type"    => "restrict",
            "options" => Ops.add(
              Ops.add(
                Ops.get_string(m, "mask", "") != "" ?
                  Ops.add(" mask ", Ops.get_string(m, "mask", "")) :
                  "",
                " "
              ),
              Ops.get_string(m, "options", "")
            )
          }
          @ntp_records = Builtins.add(@ntp_records, ret)
        end

        Builtins.y2milestone("Writing settings %1", @ntp_records)

        save2 = Builtins.flatten(Builtins.maplist(@ntp_records) do |r|
          s1 = {
            "comment" => Ops.get_string(r, "comment", ""),
            "kind"    => "value",
            "name"    => Ops.get_string(r, "type", ""),
            "type"    => 0,
            "value"   => Ops.add(
              Ops.add(Ops.get_string(r, "address", ""), " "),
              Ops.get_string(r, "options", "")
            )
          }
          s2 = nil
          if Ops.get_string(r, "type", "") == "__clock"
            s2 = {
              "comment" => Ops.get_string(r, "fudge_comment", ""),
              "kind"    => "value",
              "name"    => "fudge",
              "type"    => 0,
              "value"   => Ops.add(
                Ops.add(Ops.get_string(r, "address", ""), " "),
                Ops.get_string(r, "fudge_options", "")
              )
            }
            Ops.set(s1, "name", "server")
          end
          [s1, s2]
        end)
        save2 = Builtins.filter(save2) { |m| m != nil }

        failed = false
        conf = Convert.to_map(SCR.Read(path(".etc.ntp_conf.all")))
        if conf == nil
          failed = true
        else
          Ops.set(conf, "value", save2)
          failed = true if !SCR.Write(path(".etc.ntp_conf.all"), conf)
          failed = true if !SCR.Write(path(".etc.ntp_conf"), nil)
        end

        FileChanges.StoreFileCheckSum("/etc/ntp.conf")

        Report.Error(Message.CannotWriteSettingsTo("/etc/ntp.conf")) if failed
      end
      # write policy and run netconfig command
      SCR.Write(
        path(".sysconfig.network.config.NETCONFIG_NTP_POLICY"),
        @ntp_policy
      )
      SCR.Write(path(".sysconfig.network.config"), nil)

      if SCR.Execute(path(".target.bash"), "/sbin/netconfig update -m ntp") != 0
        # error message
        Report.Error(_("Cannot update the dynamic configuration policy."))
      end

      SCR.Write(
        path(".sysconfig.ntp.NTPD_RUN_CHROOTED"),
        @run_chroot ? "yes" : "no"
      )
      SCR.Write(path(".sysconfig.ntp"), nil)

      Builtins.sleep(sl)

      # restart daemon
      return false if Abort()
      Progress.NextStage if have_progress

      # SuSEFirewall::Write checks on its own whether there are pending
      # changes, so call it always. bnc#476951
      if true
        progress_orig = Progress.set(false)
        SuSEFirewall.Write
        Progress.set(progress_orig)
      end

      adjusted = false
      if @run_service && Service.Enable(@service_name)
        adjusted = true
      end
      if !@run_service && Service.Disable(@service_name)
        adjusted = true
      end
      unless adjusted
        # error report
        Report.Error(Message.CannotAdjustService("NTP"))
      end

      if @run_service
        unless @write_only
          # error report
          Report.Error(_("Cannot restart the NTP daemon.")) unless Service.Restart(@service_name)
        end
      else
        Service.Stop(@service_name)
      end

      if @synchronize_time
        SCR.Write(
          path(".target.string"),
          @cron_file,
          "-*/#{@sync_interval} * * * * root /usr/sbin/start-ntpd ntptimeset &>/dev/null\n"
        )
      else
        SCR.Execute(
          path(".target.bash"),
          Ops.add(
            Ops.add(
              Ops.add(Ops.add("test -e ", @cron_file), "  && rm "),
              @cron_file
            ),
            ";"
          )
        )
      end

      Builtins.sleep(sl)

      return false if Abort()
      if have_progress
        Progress.NextStage
        Progress.Title(_("Finished"))
      end
      Builtins.sleep(sl)

      return false if Abort()
      true
    end

    # Get all ntp-client settings from the first parameter
    # (For use by autoinstallation.)
    # @param [Hash] settings The YCP structure to be imported.
    # @return [Boolean] True on success
    def Import(settings)
      settings = deep_copy(settings)
      @synchronize_time = Ops.get_boolean(settings, "synchronize_time", false)
      @sync_interval = Ops.get_integer(settings, "sync_interval", 5)
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
          next deep_copy(p)
        else
          next deep_copy(p)
        end
      end
      # restricts is a list of entries whereas restrict_map
      # is a map with target key (ip, ipv4-tag, ipv6-tag,...).
      restricts = settings["restricts"] || []
      @restrict_map = {}
      restricts.each do |entry|
        target = entry.delete("target")
        @restrict_map[target] = entry
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
        values["target"] = target
        values
      end
      {
        "synchronize_time" => @synchronize_time,
        "sync_interval"    => @sync_interval,
        "start_at_boot"    => @run_service,
        "start_in_chroot"  => @run_chroot,
        "ntp_policy"       => @ntp_policy,
        "peers"            => @ntp_records,
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
        # summary string, FIXME
        summary = Summary.AddLine(summary, _("Custom configuration policy.")) # FIXME too generic!
      end

      Builtins.foreach(
        ["server", "__clock", "peer", "broadcast", "broadcastclient"]
      ) do |t|
        l = Builtins.filter(@ntp_records) do |p|
          Ops.get_string(p, "type", "") == t
        end
        names = Builtins.maplist(l) { |i| Ops.get_string(i, "address", "") }
        names = Builtins.filter(names) { |n| n != "" }
        if Ops.greater_than(Builtins.size(names), 0)
          summary = Summary.AddLine(
            summary,
            Builtins.sformat(
              Ops.get_string(types, t, ""),
              Builtins.mergestring(names, ", ")
            )
          )
        end
      end
      summary
    end

    # Test if specified NTP server answers
    # @param [String] server string host name or IP address of the NTP server
    # @param [Symbol] verbosity `no_ui: ..., `transient_popup: pop up while scanning,
    #                  `result_popup: also final pop up about the result
    # @return [Boolean] true if NTP server answers properly
    def TestNtpServer(server, verbosity)
      if verbosity != :no_ui
        UI.OpenDialog(
          # An informative popup label diring the NTP server testings
          Left(Label(_("Testing the NTP server...")))
        )
      end

      Builtins.y2milestone("Testing reachability of server %1", server)

      # testing the server using IPv4 and then using IPv6 protocol
      # bug #74076, Firewall could have been blocked IPv6
      # -K /dev/null: use /dev/null as KoD history file (if not specified,
      #               /var/db/ntp-kod will be used and it doesn't exist)
      # -c: concurrently query all IPs; -t 5: five seconds of timeout
      ret_IPv4 = SCR.Execute(path(".target.bash"), "/usr/sbin/sntp -4 -K /dev/null -t 5 -c #{server}")
      ret_IPv6 = 0
      if ret_IPv4 != 0
        ret_IPv6 = SCR.Execute(path(".target.bash"), "/usr/sbin/sntp -6 -K /dev/null -t 5 -c #{server}")
      end

      UI.CloseDialog if verbosity != :no_ui

      ok = ret_IPv4 == 0 || ret_IPv6 == 0
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
      ret = Builtins.maplist(@ntp_records) do |m|
        index = Ops.add(index, 1)
        type = Ops.get_string(m, "type", "")
        if !Builtins.contains(
            ["server", "peer", "broadcast", "broadcastclient", "__clock"],
            type
          )
          next nil
        end
        {
          "type"    => type,
          "index"   => index,
          "address" => Ops.get_string(m, "address", ""),
          "device"  => Ops.get_string(m, "device", "")
        }
      end
      ret = Builtins.filter(ret) { |m| m != nil }
      deep_copy(ret)
    end

    # Select synchronization record
    # @param [Fixnum] index integer, -1 for creating a new record
    # @return [Boolean] true on success
    def selectSyncRecord(index)
      ret = true
      if Ops.greater_or_equal(index, Builtins.size(@ntp_records)) ||
          Ops.less_than(index, -1)
        Builtins.y2error(
          "Record with index %1 doesn't exist, creating new",
          index
        )
        index = -1
        ret = false
      end
      if index == -1
        @selected_record = {}
      else
        @selected_record = Ops.get(@ntp_records, index, {})
      end
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
      if Ops.greater_or_equal(index, Builtins.size(@ntp_records)) ||
          Ops.less_or_equal(index, -1)
        Builtins.y2error("Record with index %1 doesn't exist", index)
        return false
      end
      Ops.set(@ntp_records, index, nil)
      @ntp_records = Builtins.filter(@ntp_records) { |r| r != nil }
      @modified = true
      true
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

    publish :variable => :AbortFunction, :type => "boolean ()"
    publish :variable => :modified, :type => "boolean"
    publish :variable => :write_only, :type => "boolean"
    publish :variable => :ntp_records, :type => "list <map <string, any>>"
    publish :variable => :restrict_map, :type => "map <string, map <string, any>>"
    publish :variable => :run_service, :type => "boolean"
    publish :variable => :synchronize_time, :type => "boolean"
    publish :variable => :sync_interval, :type => "integer"
    publish :variable => :cron_file, :type => "string"
    publish :variable => :service_name, :type => "string"
    publish :variable => :run_chroot, :type => "boolean"
    publish :variable => :ntp_policy, :type => "string"
    publish :variable => :selected_index, :type => "integer"
    publish :variable => :selected_record, :type => "map <string, any>"
    publish :variable => :ad_controller, :type => "string"
    publish :variable => :change_firewall, :type => "boolean"
    publish :variable => :required_packages, :type => "list"
    publish :variable => :firewall_services, :type => "list <string>"
    publish :variable => :simple_dialog, :type => "boolean"
    publish :variable => :config_has_been_read, :type => "boolean"
    publish :variable => :ntp_selected, :type => "boolean"
    publish :function => :PolicyIsAuto, :type => "boolean ()"
    publish :function => :PolicyIsNomodify, :type => "boolean ()"
    publish :function => :PolicyIsNonstatic, :type => "boolean ()"
    publish :function => :GetAllKnownCountries, :type => "map <string, string> ()"
    publish :function => :GetCurrentLanguageCode, :type => "string ()"
    publish :function => :GetNtpServers, :type => "map <string, map <string, string>> ()"
    publish :function => :GetCountryNames, :type => "map <string, string> ()"
    publish :function => :GetNtpServersByCountry, :type => "list (string, boolean)"
    publish :function => :ProcessNtpConf, :type => "boolean ()"
    publish :function => :ReadSynchronization, :type => "boolean ()"
    publish :function => :Read, :type => "boolean ()"
    publish :function => :GetUsedNtpServers, :type => "list <string> ()"
    publish :variable => :random_pool_servers, :type => "list <string>"
    publish :function => :IsRandomServersServiceEnabled, :type => "boolean ()"
    publish :function => :DeActivateRandomPoolServersFunction, :type => "void ()"
    publish :function => :ActivateRandomPoolServersFunction, :type => "void ()"
    publish :function => :Write, :type => "boolean ()"
    publish :function => :Import, :type => "boolean (map)"
    publish :function => :Export, :type => "map ()"
    publish :function => :Summary, :type => "string ()"
    publish :function => :TestNtpServer, :type => "boolean (string, symbol)"
    publish :function => :DetectNtpServers, :type => "list <string> (symbol)"
    publish :function => :getSyncRecords, :type => "list <map <string, any>> ()"
    publish :function => :selectSyncRecord, :type => "boolean (integer)"
    publish :function => :findSyncRecord, :type => "integer (string, string)"
    publish :function => :storeSyncRecord, :type => "boolean ()"
    publish :function => :deleteSyncRecord, :type => "boolean (integer)"
    publish :function => :enableOptionInSyncRecord, :type => "void (string)"
    publish :function => :AutoPackages, :type => "map ()"
  end

  NtpClient = NtpClientClass.new
  NtpClient.main
end
