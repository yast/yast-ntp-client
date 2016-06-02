require_relative "test_helper"

Yast.import "NtpClient"
Yast.import "NetworkInterfaces"
Yast.import "PackageSystem"
Yast.import "Service"

describe Yast::NtpClient do

  subject { Yast::NtpClient }

  describe "#Read" do
    before do
      subject.config_has_been_read = false
      allow(Yast::NetworkInterfaces).to receive(:Read)
      allow(subject).to receive(:Abort).and_return(false)
      allow(Yast::Mode).to receive(:normal).and_return(false)
      allow(Yast::Progress).to receive(:set)
      allow(Yast::SCR).to receive(:Read)
        .with(Yast::Path.new(".sysconfig.network.config.NETCONFIG_NTP_POLICY"))
        .and_return(nil)
      allow(Yast::PackageSystem).to receive(:CheckAndInstallPackagesInteractive)
        .with(["ntp"]).and_return(true)
      allow(subject).to receive(:GetNtpServers)
      allow(subject).to receive(:GetCountryNames)
      allow(Yast::FileUtils).to receive(:Exists)
        .with("#{Yast::Directory.vardir}/ad_ntp_data.ycp").and_return(false)
      allow(Yast::FileChanges).to receive(:CheckFiles)
        .with(["/etc/ntp.conf"]).and_return(true)
      allow(subject).to receive(:ProcessNtpConf)
      allow(subject).to receive(:ReadSynchronization)
      allow(Yast::SuSEFirewall).to receive(:Read)
      allow(Yast::SCR).to receive(:Read)
        .with(Yast::Path.new(".sysconfig.ntp.NTPD_RUN_CHROOTED"))
        .and_return(nil)
      allow(Yast::Service).to receive(:Enabled).with("ntpd").and_return(true)
    end

    it "returns true if config was read previously" do
      subject.config_has_been_read = true
      expect(Yast::Mode).not_to receive(:normal)

      expect(subject.Read).to eql(true)
    end

    it "returns false if abort is pressed" do
      allow(subject).to receive(:Abort).and_return(true)

      expect(subject.Read).to eql(false)
    end

    it "doesn't show progress if it is not in normal Mode" do
      expect(Yast::Progress).not_to receive(:New)

      subject.Read
    end

    it "reads network interfaces config" do
      expect(Yast::NetworkInterfaces).to receive(:Read)

      subject.Read
    end

    it "reads ntp policy setting, using auto as default if not exists" do
      expect(Yast::SCR).to receive(:Read)
        .with(Yast::Path.new(".sysconfig.network.config.NETCONFIG_NTP_POLICY"))
        .and_return(nil)
      expect(subject.ntp_policy).to eql("auto")

      subject.Read
    end

    it "loads known ntp servers and known country names" do
      expect(subject).to receive(:GetNtpServers)
      expect(subject).to receive(:GetCountryNames)

      subject.Read
    end

    it "returns false if the ntp package is not and could not be installed" do
      expect(Yast::PackageSystem).to receive(:CheckAndInstallPackagesInteractive)
        .with(["ntp"]).and_return(false)
      expect(Yast::Service).not_to receive(:Enabled)

      expect(subject.Read).to eql(false)
    end

    it "checks if ntpd service is enable" do
      expect(Yast::Service).to receive(:Enabled).with("ntpd")

      subject.Read
    end

    it "checks active directory's ntp dumped data file" do
      expect(Yast::FileUtils).to receive(:Exists).with("#{Yast::Directory.vardir}/ad_ntp_data.ycp")

      subject.Read
    end

    it "reads ntp config from /etc/ntp.conf" do
      expect(subject).to receive(:ProcessNtpConf)

      subject.Read
    end

    it "reads synchronization config" do
      expect(subject).to receive(:ReadSynchronization)

      subject.Read
    end

    it "reads ntpd chroot configuration" do
      expect(Yast::SCR).to receive(:Read)
        .with(Yast::Path.new(".sysconfig.ntp.NTPD_RUN_CHROOTED"))

      subject.Read
    end

    it "returns true if all reads were performed" do
      expect(subject.Read).to eql(true)
    end
  end

  describe "#Write" do
    let(:data_dir) { File.join(File.dirname(__FILE__), "data") }

    around do |example|
      ::FileUtils.cp(File.join(data_dir, "scr_root/etc/ntp.conf.original"),
        File.join(data_dir, "scr_root/etc/ntp.conf"))
      change_scr_root(File.join(data_dir, "scr_root"), &example)
    end

    before do
      allow(Yast::Mode).to receive(:normal).and_return(false)
      allow(subject).to receive(:Abort).and_return(false)
      allow(Yast::SCR).to receive(:Read)
        .with(Yast::Path.new(".etc.ntp_conf.all")).and_return(nil)
      allow(Yast::FileChanges).to receive(:StoreFileCheckSum).with("/etc/ntp.conf")
      allow(Yast::SCR).to receive(:Write)
        .with(Yast::Path.new(".sysconfig.network.config.NETCONFIG_NTP_POLICY"), anything)
      allow(Yast::SCR).to receive(:Write)
        .with(Yast::Path.new(".sysconfig.network.config"), nil)
      allow(Yast::SCR).to receive(:Execute)
        .with(Yast::Path.new(".target.bash"), "/sbin/netconfig update -m ntp")
        .and_return(0)
      allow(Yast::SCR).to receive(:Write)
        .with(Yast::Path.new(".sysconfig.ntp.NTPD_RUN_CHROOTED"), anything)
      allow(Yast::SCR).to receive(:Write)
        .with(Yast::Path.new(".sysconfig.ntp"), nil)
      allow(Yast::SCR).to receive(:Execute)
        .with(Yast::Path.new(".target.bash"),
          "test -e #{subject.cron_file} && rm #{subject.cron_file};")
      allow(Yast::SuSEFirewall).to receive(:Write)
      allow(Yast::Service).to receive(:Enable)
      allow(Yast::Service).to receive(:Disable)
      allow(Yast::Service).to receive(:Restart)
      allow(Yast::Service).to receive(:Stop)
      allow(Yast::Report).to receive(:Error)
      allow(Yast::SCR).to receive(:Execute)
        .with(Yast::Path.new(".target.string"),
          subject.cron_file,
          "test -e #{subject.cron_file} && rm #{subject.cron_file};"
               )
    end

    it "doesn't show progress if it is not in normal Mode" do
      expect(Yast::Progress).not_to receive(:New)

      subject.Write
    end

    it "returns false if abort is pressed" do
      allow(subject).to receive(:Abort).and_return(true)

      expect(subject.Write).to eql(false)
    end

    it "reads current /etc/ntp.conf config" do
      expect(Yast::SCR).to receive(:Read).with(Yast::Path.new(".etc.ntp_conf.all"))

      subject.Write
    end

    context "when /etc/ntp.conf exists" do
      let(:conf) do
        { "comment" => "",
          "file"    => -1,
          "kind"    => "section",
          "name"    => "",
          "type"    => -1,
          "value"   => []
        }
      end

      before do
        allow(Yast::SCR).to receive(:Read)
          .with(Yast::Path.new(".etc.ntp_conf.all")).and_call_original
      end

      it "tries to write to it current ntp entries" do
        expect(Yast::SCR).to receive(:Write).with(Yast::Path.new(".etc.ntp_conf.all"), conf)
        expect(Yast::SCR).to receive(:Write).with(Yast::Path.new(".etc.ntp_conf"), nil)

        subject.Write
      end

      it "reports and error if not able to write /etc/ntp.conf file" do
        allow(Yast::SCR).to receive(:Write)
          .with(Yast::Path.new(".etc.ntp_conf.all"), conf).and_return(false)
        allow(Yast::SCR).to receive(:Write)
          .with(Yast::Path.new(".etc.ntp_conf"), nil).and_return(false)
        expect(Yast::Report).to receive(:Error)
          .with(Yast::Message.CannotWriteSettingsTo("/etc/ntp.conf"))

        subject.Write
      end
    end

    it "stores /etc/ntp.conf checksum" do
      expect(Yast::FileChanges).to receive(:StoreFileCheckSum).with("/etc/ntp.conf")

      subject.Write
    end

    it "updates netconfig ntp config" do
      subject.ntp_policy = "manual"
      expect(Yast::SCR).to receive(:Write)
        .with(Yast::Path.new(".sysconfig.network.config.NETCONFIG_NTP_POLICY"), "manual")
      expect(Yast::SCR).to receive(:Execute)
        .with(Yast::Path.new(".target.bash"), "/sbin/netconfig update -m ntp")

      subject.Write
    end

    it "writes sysconfig ntp chrooted option with current value" do
      subject.run_chroot = true
      expect(Yast::SCR).to receive(:Write)
        .with(Yast::Path.new(".sysconfig.ntp.NTPD_RUN_CHROOTED"), "yes")
      expect(Yast::SCR).to receive(:Write)
        .with(Yast::Path.new(".sysconfig.ntp"), nil)

      subject.Write
    end

    it "calls SuSEFirewall.Write to check pending changes" do
      expect(Yast::SuSEFirewall).to receive(:Write)
      subject.Write
    end

    context "when ntp has been configured to run as a service" do
      before do
        subject.run_service = true
        subject.write_only = false
      end

      it "enables ntp service" do
        expect(Yast::Service).to receive(:Enable).with(subject.service_name)
        subject.Write
      end

      context "when it is in write only mode" do
        it "doesn't try to restart ntp service" do
          subject.write_only = true
          expect(Yast::Service).not_to receive(:Restart).with(subject.service_name)

          subject.Write
        end
      end

      context "when it is not in write only mode" do
        it "tries to restart ntp service" do
          expect(Yast::Service).to receive(:Restart).with(subject.service_name)

          subject.Write
        end
      end
    end

    context "when has not been configured to run as a service" do
      before do
        subject.run_service = false
      end

      it "disables ntp service" do
        expect(Yast::Service).to receive(:Disable).with(subject.service_name)
        expect(Yast::Service).to receive(:Stop).with(subject.service_name)
        subject.Write
      end
    end

    context "when synchronize time is false" do
      it "writes cronfile to sync ntp via cron" do
        subject.synchronize_time = false
        expect(Yast::SCR).to receive(:Execute)
          .with(Yast::Path.new(".target.bash"),
            "test -e #{subject.cron_file} && rm #{subject.cron_file};"
               )

        subject.Write
      end
    end

    context "when synchronize time is true" do
      let(:cron_entry) do
        "-*/#{subject.sync_interval} * * * * root /usr/sbin/start-ntpd ntptimeset &>/dev/null\n"
      end
      it "writes cronfile to sync ntp via cron" do
        subject.synchronize_time = true
        expect(Yast::SCR).to receive(:Write)
          .with(Yast::Path.new(".target.string"), subject.cron_file, cron_entry)

        subject.Write
      end
    end

    it "returns true if not aborted" do
      expect(subject.Write).to eql(true)
    end
  end

  describe "#GetNtpServers" do
    let(:country_servers) do
      { "tick.nap.com.ar" =>
        { "access_policy "  => "open access, please send a message to notify",
          "address"         => "tick.nap.com.ar",
          "country"         => "AR",
          "exact_location"  => "Network Access Point, Buenos Aires, Argentina",
          "location"        => "Argentina",
          "stratum"         => "2",
          "synchronization" => "NTP V3 secondary (stratum 2), Cisco IOS"
        }
      }
    end

    context "when ntp servers haven't been read before" do
      it "returns empty hash in test Mode" do
        allow(Yast::Mode).to receive(:test).and_return(true)

        expect(subject.GetNtpServers).to eql({})
      end

      it "caches known ntp servers" do
        allow(Yast::Mode).to receive(:test).and_return(false)
        subject.instance_variable_set(:@ntp_servers, nil)
        expect(subject).to receive(:update_ntp_servers!)

        subject.GetNtpServers
      end

      it "return known ntp servers" do
        subject.instance_variable_set(:@ntp_servers, country_servers)

        expect(subject.GetNtpServers).to eql(country_servers)
      end
    end

    context "when ntp servers haven been read before" do

      before do
        subject.instance_variable_set(:@ntp_servers, country_servers)
      end

      it "returns known ntp servers" do
        expect(subject.GetNtpServers).to eql(country_servers)
      end
    end

  end

  describe "#reachable_ntp_server?" do
    context "given a server" do
      it "returns true if sntp test passed with IPv4 or/and with IPv6" do
        allow(subject).to receive(:sntp_test).with("server").and_return(true, false, true)
        allow(subject).to receive(:sntp_test).with("server", 6).and_return(true, true)

        expect(subject.reachable_ntp_server?("server")).to eql(true)
        expect(subject.reachable_ntp_server?("server")).to eql(true)
        expect(subject.reachable_ntp_server?("server")).to eql(true)
      end

      it "returns false if sntp test fails with IPv4 or/and with IPv6" do
        allow(subject).to receive(:sntp_test).with("server").and_return(false)
        allow(subject).to receive(:sntp_test).with("server", 6).and_return(false)

        expect(subject.reachable_ntp_server?("server")).to eql(false)
      end
    end

  end

  describe "#sntp_test" do
    let(:ip_version) { 4 }
    let(:server) { "sntp.server.de" }
    let(:output) { { "stdout" => "", "stderr" => "", "exit" => 0 } }

    context "given a server" do
      context "when no ip_version is passed as argument" do
        let(:output) do
          {
            "stderr" => "server_name lookup error Name or service not known",
            "stdout" => "sntp 4.2.8p7@1.3265-o Thu May 12 16:14:59 UTC 2016",
            "exit"   => 0
          }
        end
        it "calls sntp command with ip version 4 by default" do
          expect(Yast::SCR).to receive(:Execute)
            .with(Yast::Path.new(".target.bash_output"),
              "LANG=C /usr/sbin/sntp -#{ip_version} -K /dev/null -t 5 -c #{server}")
            .and_return(output)

          subject.sntp_test(server)
        end

        it "returns false if server is not reachable" do
          expect(Yast::SCR).to receive(:Execute)
            .with(path(".target.bash_output"),
              "LANG=C /usr/sbin/sntp -#{ip_version} -K /dev/null -t 5 -c #{server}")
            .and_return(output)

          expect(subject.sntp_test(server)).to eql(false)
        end

        it "returns true if sntp command's exit code is 0" do
          output["stderr"] = ""
          expect(Yast::SCR).to receive(:Execute)
            .with(path(".target.bash_output"),
              "LANG=C /usr/sbin/sntp -#{ip_version} -K /dev/null -t 5 -c #{server}")
            .and_return(output)

          expect(subject.sntp_test(server)).to eql(true)
        end
      end
    end
  end

  describe "TestNtpServer" do
    it "returns true if ntp server is reachable" do
      allow(subject).to receive(:reachable_ntp_server?).with("server") { true }
      expect(subject.TestNtpServer("server", "")).to eql(true)
    end
    it "returns false if ntp server is not reachable" do
      allow(subject).to receive(:reachable_ntp_server?).with("server") { false }
      expect(subject.TestNtpServer("server", "")).to eql(false)
    end

    context "when given verbosity is no ui" do
      it "doesn't show any dialog" do
        expect(Yast::Popup).to receive(:Feedback).never
      end
    end
  end
end
