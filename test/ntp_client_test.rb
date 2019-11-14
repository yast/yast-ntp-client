require_relative "test_helper"

require "fileutils"
require "cfa/memory_file"

Yast.import "NtpClient"
Yast.import "NetworkInterfaces"
Yast.import "PackageSystem"
Yast.import "Service"

describe Yast::NtpClient do

  subject do
    cl = Yast::NtpClientClass.new
    cl.main
    cl
  end

  let(:data_dir) { File.join(File.dirname(__FILE__), "data") }

  around do |example|
    ::FileUtils.cp(File.join(data_dir, "scr_root/etc/chrony.conf.original"),
      File.join(data_dir, "scr_root/etc/chrony.conf"))
    change_scr_root(File.join(data_dir, "scr_root"), &example)
    ::FileUtils.rm(File.join(data_dir, "scr_root/etc/chrony.conf"))
  end

  # mock to allow read of scr chrooted env
  before do
    subject.config_has_been_read = false
    allow(subject).to receive(:Abort).and_return(false)
    allow(subject).to receive(:go_next).and_return(true)
    allow(subject).to receive(:progress?).and_return(false)
    allow(Yast::Service).to receive(:Enabled).with("chronyd").and_return(true)
    allow(Yast::NetworkInterfaces).to receive(:Read)
    allow(Yast::Progress)
    allow(Yast::PackageSystem).to receive(:CheckAndInstallPackagesInteractive)
      .with(["chrony"]).and_return(true)
  end

  describe "#AutoYaST methods" do
    let(:ntp_client_section) do
      {
        "ntp_policy"  => "eth*",
        "ntp_servers" => [
          "iburst"  => false,
          "address" => "cz.pool.ntp.org",
          "offline" => true
        ],
        "ntp_sync"    => "15"
      }
    end

    describe "#Import" do
      before(:each) do
        subject.Import(ntp_client_section)
      end

      context "with a correct AutoYaST configuration file" do
        it "sets properly netconfig policy" do
          expect(subject.ntp_policy).to eq "eth*"
        end

        it "sets properly running of daemon" do
          expect(subject.run_service).to eq false
          expect(subject.synchronize_time).to eq true
          expect(subject.sync_interval).to eq 15
        end

        it "sets new servers" do
          expect(subject.ntp_conf.pools).to eq(
            "cz.pool.ntp.org" => { "offline" => nil }
          )
        end
      end

      context "with an empty AutoYaST configuration" do
        let(:ntp_client_section) { {} }

        it "clears all ntp servers" do
          expect(subject.GetUsedNtpServers).to be_empty
        end

        it "sets default synchronize flag" do
          expect(subject.synchronize_time).to eq false
        end

        it "sets default start at boot flag" do
          expect(subject.run_service).to eq true
        end

        it "sets default policy" do
          expect(subject.ntp_policy).to eq "auto"
        end

        it "set default sync intervall" do
          expect(subject.sync_interval).to eq 5
        end
      end
    end

    describe "#Export" do
      let(:profile_name) { "autoinst.xml" }
      let(:ntp_conf) do
        path = File.expand_path("fixtures/cfa/chrony.conf", __dir__)
        text = File.read(path)
        file = CFA::MemoryFile.new(text)
        CFA::ChronyConf.new(file_handler: file)
      end

      it "produces an output equivalent to #Import" do
        subject.Import(ntp_client_section)
        expect(subject.Export()).to eq ntp_client_section
      end

      it "clones without encountering a CFA object" do
        allow(subject).to receive(:ntp_conf).and_return(ntp_conf)
        subject.config_has_been_read = false
        subject.ProcessNtpConf
        exported = subject.Export
        # This passes the exported value thru the component system.
        # It would blow up if we forgot a CFA object inside, bsc#1058510
        expect { Yast::WFM.Execute(path(".foo"), exported) }.to_not raise_error
      end
    end
  end

  describe "#Read" do
    before do
      subject.config_has_been_read = false
      allow(subject).to receive(:Abort).and_return(false)
      allow(subject).to receive(:Abort).and_return(false)
      allow(subject).to receive(:go_next).and_return(true)
      allow(subject).to receive(:progress?).and_return(false)
      allow(subject).to receive(:read_ad_address!)
      allow(subject).to receive(:ProcessNtpConf)
      allow(subject).to receive(:ReadSynchronization)
      allow(subject).to receive(:read_policy!)
      allow(Yast::Service).to receive(:Enabled).with("chronyd").and_return(true)
      allow(Yast::NetworkInterfaces).to receive(:Read)
      allow(Yast::Progress)
      allow(Yast::PackageSystem).to receive(:CheckAndInstallPackagesInteractive)
        .with(["chrony"]).and_return(true)
    end

    context "when config has been read previously" do
      it "returns true" do
        subject.config_has_been_read = true
        expect(Yast::Mode).not_to receive(:normal)

        expect(subject.Read).to eql(true)
      end
    end

    context "when config has not been read" do
      before do
        subject.config_has_been_read = false
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

      it "reads ntp policy" do
        expect(subject).to receive(:read_policy!)

        subject.Read
      end

      it "loads known ntp servers and known country names" do
        expect(subject).to receive(:GetNtpServers)
        expect(subject).to receive(:GetCountryNames)

        subject.Read
      end

      context "when Mode is not installation" do
        it "returns false if the ntp package neither is installed nor available" do
          expect(Yast::PackageSystem).to receive(:CheckAndInstallPackagesInteractive)
            .with(["chrony"]).and_return(false)
          expect(Yast::Service).not_to receive(:Enabled)

          expect(subject.Read).to eql(false)
        end
      end

      it "checks if chronyd service is enable" do
        expect(Yast::Service).to receive(:Enabled).with("chronyd")

        subject.Read
      end

      context "when active directory's ntp dumped data file exists" do
        it "reads active directory address from file" do
          expect(subject).to receive(:read_ad_address!)

          subject.Read
        end
      end

      it "reads ntp config from /etc/ntp.conf" do
        expect(subject).to receive(:ProcessNtpConf)

        subject.Read
      end

      it "reads synchronization config" do
        expect(subject).to receive(:ReadSynchronization)

        subject.Read
      end

      it "returns true if all reads were performed" do
        expect(subject.Read).to eql(true)
      end
    end
  end

  describe "#Write" do
    before do
      allow(subject).to receive(:Abort).and_return(false)
      allow(subject).to receive(:go_next).and_return(true)
      allow(subject).to receive(:progress?).and_return(false)
      allow(subject).to receive(:write_ntp_conf).and_return(true)
      allow(subject).to receive(:write_and_update_policy).and_return(true)
      allow(subject).to receive(:check_service)

      allow(Yast::Report)
    end

    it "returns false if abort is pressed" do
      allow(subject).to receive(:Abort).and_return(true)
      expect(subject).to receive(:go_next).and_call_original

      expect(subject.Write).to eql(false)
    end

    it "writes current ntp records to ntp config" do
      expect(subject).to receive(:write_ntp_conf)

      subject.Write
    end

    it "writes new ntp records to ntp config" do
      expect(subject).to receive(:write_ntp_conf).and_call_original
      expect(Yast::Report).to_not receive(:Error)
      subject.ProcessNtpConf

      subject.ntp_conf.clear_pools
      subject.ntp_conf.add_pool("tik.cesnet.cz")

      expect(subject.Write).to eq true
      lines = File.read(File.join(data_dir, "scr_root/etc/chrony.conf"))
      expect(lines.lines).to include("pool tik.cesnet.cz iburst\n")
    end

    it "writes ntp policy and updates ntp with netconfig" do
      expect(subject).to receive(:write_and_update_policy)

      subject.Write
    end

    context "services will be started" do
      before do
        subject.run_service = true
        subject.write_only = false
      end

      context "when product require precise time" do
        before do
          allow(Yast::ProductFeatures).to receive(:GetBooleanFeature).and_return(true)
        end

        it "enables and restarts services including chrony-wait" do
          allow(subject).to receive(:check_service).and_call_original
          expect(Yast::Service).to receive(:Enable).with("chronyd").and_return(true)
          expect(Yast::Service).to receive(:Enable).with("chrony-wait").and_return(true)
          expect(Yast::Service).to receive(:Restart).with("chronyd").and_return(true)
          expect(Yast::Service).to receive(:Restart).with("chrony-wait").and_return(true)

          subject.Write
        end
      end

      context "when product does not require precise time" do
        before do
          allow(Yast::ProductFeatures).to receive(:GetBooleanFeature).and_return(false)
        end

        it "enables and restarts services without chrony-wait" do
          allow(subject).to receive(:check_service).and_call_original
          expect(Yast::Service).to receive(:Enable).with("chronyd").and_return(true)
          expect(Yast::Service).to_not receive(:Enable).with("chrony-wait")
          expect(Yast::Service).to receive(:Restart).with("chronyd").and_return(true)
          expect(Yast::Service).to_not receive(:Restart).with("chrony-wait")

          subject.Write
        end
      end
    end

    context "services will be stopped" do
      before do
        subject.run_service = false
      end

      it "disables and stops services" do
        allow(subject).to receive(:check_service).and_call_original
        expect(Yast::Service).to receive(:Disable).with("chronyd").and_return(true)
        expect(Yast::Service).to receive(:Disable).with("chrony-wait").and_return(true)
        expect(Yast::Service).to receive(:Stop).with("chronyd").and_return(true)
        expect(Yast::Service).to receive(:Stop).with("chrony-wait").and_return(true)

        subject.Write
      end
    end

    it "updates systemd timer settings" do
      expect(subject).to receive(:update_timer_settings)

      subject.Write
    end

    it "returns true if not aborted" do
      expect(subject.Write).to eql(true)
    end
  end

  describe "#MakePoolRecord" do
    let(:record) do
      {
        "address"  => "de.pool.ntp.org",
        "country"  => "DE",
        "location" => "some location"
      }
    end
    let(:uk_record) do
      {
        "address"  => "uk.pool.ntp.org",
        "country"  => "GB",
        "location" => "some UK location"
      }
    end

    it "returns a pool ntp record for the given country code and location" do
      expect(subject.MakePoolRecord("DE", "some location")).to eql(record)
    end

    it "returns a pool ntp record with 'uk.pool.ntp.org' address if country code is GB" do
      expect(subject.MakePoolRecord("GB", "some UK location")).to eql(uk_record)
    end
  end

  describe "#GetNtpServers" do
    let(:country_servers) do
      {
        "tick.nap.com.ar" =>
                             {
                               "access_policy "  => "open access, please send a message to notify",
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
      it "caches known ntp servers" do
        allow(Yast::Mode).to receive(:test).and_return(false)
        subject.instance_variable_set(:@ntp_servers, nil)
        expect(subject).to receive(:update_ntp_servers!)

        subject.GetNtpServers
      end

      it "returns known ntp servers" do
        subject.instance_variable_set(:@ntp_servers, country_servers)

        expect(subject.GetNtpServers).to eql(country_servers)
      end
    end

    context "when ntp servers have been read before" do

      before do
        subject.instance_variable_set(:@ntp_servers, country_servers)
      end

      it "returns known ntp servers" do
        expect(subject.GetNtpServers).to eql(country_servers)
      end
    end

  end

  describe "#GetNtpServersByCountry" do
    it "gets all ntp servers" do
      expect(subject).to receive(:GetNtpServers).and_call_original

      subject.GetNtpServersByCountry("", false)
    end

    it "gets all country names if given country name is an empty string" do
      expect(subject).to receive(:GetNtpServers).and_call_original
      expect(subject).to receive(:GetCountryNames).and_call_original

      subject.GetNtpServersByCountry("", false)
    end

    pending("returns a list of items with read servers")
  end

  describe "#ReadSynchronization" do
    let(:systemd_timer_file) { "/etc/systemd/system/yast-timesync.timer" }
    let(:timer_content) { "" }

    before do
      allow(::File).to receive(:exist?).and_call_original
      allow(::File).to receive(:exist?).with("/etc/systemd/system/yast-timesync.timer")
        .and_return(true)
      allow(::File).to receive(:read).and_return(timer_content)
    end

    it "reads systemd timer" do
      expect(::File).to receive(:read).and_return(timer_content)

      subject.ReadSynchronization
    end

    context "when systemd timer file does not exist" do
      before do
        allow(::File).to receive(:exist?).with("/etc/systemd/system/yast-timesync.timer")
          .and_return(true)
      end

      it "sets synchronize_time as false" do
        subject.ReadSynchronization

        expect(subject.synchronize_time).to eql(false)
      end

      it "sets sync interval with default value" do
        subject.ReadSynchronization

        expect(subject.sync_interval).to eql(Yast::NtpClientClass::DEFAULT_SYNC_INTERVAL)
      end
    end

    context "when systemd timer file exists" do
      let(:timer_content) do
        subject.sync_interval = 10
        subject.send(:timer_content)
      end

      context "when timer is not active" do
        before do
          allow(Yast::SCR).to receive(:Execute).and_return("exit" => 3)
        end

        it "sets synchronize_time as false" do
          subject.ReadSynchronization

          expect(subject.synchronize_time).to eql(false)
        end

        it "sets sync interval with value from timer" do
          subject.ReadSynchronization

          expect(subject.sync_interval).to eql(10)
        end
      end

      context "when timer is active" do
        before do
          allow(Yast::SCR).to receive(:Execute).and_return("exit" => 0)
        end

        it "sets synchronize time as true" do
          expect(subject.ReadSynchronization).to eql(true)
        end

        it "sets sync_interval with value from timer" do
          subject.ReadSynchronization

          expect(subject.sync_interval).to eql(10)
        end
      end
    end
  end

  describe "#reachable_ntp_server?" do
    context "given a server" do
      it "returns true if ntp test passed with IPv4" do
        expect(subject).to receive(:ntp_test).with("server").and_return(true)
        expect(subject).not_to receive(:ntp_test).with("server", 6)

        expect(subject.reachable_ntp_server?("server")).to eql(true)
      end

      it "returns true if ntp test passed with IPv6" do
        expect(subject).to receive(:ntp_test).with("server").and_return(false)
        expect(subject).to receive(:ntp_test).with("server", 6).and_return(true)

        expect(subject.reachable_ntp_server?("server")).to eql(true)
      end

      it "returns false if ntp test fails with IPv4 and with IPv6" do
        expect(subject).to receive(:ntp_test).with("server").and_return(false)
        expect(subject).to receive(:ntp_test).with("server", 6).and_return(false)

        expect(subject.reachable_ntp_server?("server")).to eql(false)
      end
    end
  end

  describe "#sync_once" do
    let(:output) { { "stdout" => "", "stderr" => "", "exit" => 0 } }
    let(:server) { "sntp.server.de" }

    before do
      allow(Yast::SCR).to receive(:Execute)
    end

    it "syncs the system time against the specified server" do
      expect(Yast::SCR).to receive(:Execute)
        .with(Yast::Path.new(".target.bash_output"),
          "/usr/sbin/chronyd -q -t 30 'pool #{server} iburst'")
        .and_return(output)

      subject.sync_once(server)
    end

    it "returns the syncronization exit code" do
      expect(Yast::SCR).to receive(:Execute)
        .with(Yast::Path.new(".target.bash_output"),
          "/usr/sbin/chronyd -q -t 30 'pool #{server} iburst'")
        .and_return(output)

      expect(subject.sync_once(server)).to eql(0)
    end
  end

  describe "#ntp_test" do
    let(:ip_version) { 4 }
    let(:server) { "sntp.server.de" }
    let(:output) { { "stdout" => "", "stderr" => "", "exit" => 0 } }

    it "calls ntp command with ip version 4 by default" do
      expect(Yast::SCR).to receive(:Execute)
        .with(Yast::Path.new(".target.bash_output"),
          /\/usr\/sbin\/chronyd.*#{server}/)
        .and_return(output)

      subject.ntp_test(server)
    end

    it "returns false if chronyd returns non-zero" do
      output["exit"] = 1
      expect(Yast::SCR).to receive(:Execute)
        .with(path(".target.bash_output"),
          /\/usr\/sbin\/chronyd.*#{server}/)
        .and_return(output)

      expect(subject.ntp_test(server)).to eql(false)
    end

    it "returns true if chronyd command's exit code is 0" do
      output["stdout"] = "sntp 4.2.8p8@1.3265-o Fri Sep 30 15:52:10 UTC 2016 (1)\n"
      expect(Yast::SCR).to receive(:Execute)
        .with(path(".target.bash_output"),
          /\/usr\/sbin\/chronyd.*#{server}/)
        .and_return(output)

      expect(subject.ntp_test(server)).to eql(true)
    end
  end

  describe "#TestNtpServer" do
    it "returns true if ntp server is reachable" do
      allow(subject).to receive(:reachable_ntp_server?).with("server") { true }
      expect(subject.TestNtpServer("server", "")).to eql(true)
    end
    it "returns false if ntp server is not reachable" do
      allow(subject).to receive(:reachable_ntp_server?).with("server") { false }
      expect(subject.TestNtpServer("server", "")).to eql(false)
    end

    context "when given verbosity is :no_ui" do
      it "doesn't show any dialog" do
        expect(Yast::Popup).to receive(:Feedback).never
        expect(Yast::Popup).to receive(:Notify).never
        expect(Yast::Report).to receive(:Error).never

        subject.TestNtpServer("server", :no_ui)
      end
    end

    context "when given verbosity is :result_popup" do
      it "shows Feedback Popup" do
        expect(Yast::Popup).to receive(:Feedback).once

        subject.TestNtpServer("server", :whatever)
      end

      it "notifies with a Popup if success" do
        allow(subject).to receive(:reachable_ntp_server?).with("server") { true }
        expect(Yast::Popup).to receive(:Notify).once
        expect(Yast::Report).to receive(:Error).never

        subject.TestNtpServer("server", :result_popup)
      end

      it "reports with an error if not reachable server" do
        allow(subject).to receive(:reachable_ntp_server?).with("server") { false }
        expect(Yast::Popup).to receive(:Notify).never
        expect(Yast::Report).to receive(:Error).once

        subject.TestNtpServer("server", :result_popup)
      end
    end

    context "when given vervosity is any other argument" do
      it "only shows Feedback Popup" do
        expect(Yast::Popup).to receive(:Feedback).once
        expect(Yast::Popup).to receive(:Notify).never
        expect(Yast::Report).to receive(:Error).never

        subject.TestNtpServer("server", :whatever)
      end
    end
  end

  describe "#GetUsedNtpServers" do
    let(:used_ntp_servers) do
      ["2.opensuse.pool.ntp.org"]
    end

    it "returns a list of NTP servers used in the current configuration" do
      subject.Read

      expect(subject.GetUsedNtpServers).to eql(used_ntp_servers)
    end
  end

  describe "#ProcessNtpConf" do
    it "returns false if config has been read previously" do
      subject.instance_variable_set(:@config_has_been_read, true)
      expect(subject.ProcessNtpConf).to eql(false)
    end

    it "returns false if config doesn't exist" do
      allow(Yast::FileUtils).to receive(:Exists).with("/etc/chrony.conf").and_return(false)
      expect(subject.ProcessNtpConf).to eql(false)
    end

    it "sets configuration as read and returns true" do
      expect(subject.ProcessNtpConf).to eql(true)
      expect(subject.config_has_been_read).to eql(true)
    end
  end

  describe "#read_ad_address!" do

    context "when there is an active directory data file" do
      before do
        allow(Yast::Directory).to receive(:find_data_file).with("ad_ntp_data.ycp")
          .and_return("/usr/share/YaST2/data/ad_ntp_data.ycp")
        allow(Yast::SCR).to receive(:Execute)
          .with(path(".target.remove"), "/usr/share/YaST2/data/ad_ntp_data.ycp")
      end

      it "reads and sets active directory controller" do
        subject.send(:read_ad_address!)

        expect(subject.ad_controller).to eql("ads.suse.de")
      end

      it "removes data file if controller is read" do
        expect(Yast::SCR).to receive(:Execute)
          .with(path(".target.remove"), "/usr/share/YaST2/data/ad_ntp_data.ycp")

        subject.send(:read_ad_address!)
      end
    end
  end

  describe "#update_ntp_servers!" do
    let(:data_dir) { File.join(File.dirname(__FILE__), "data") }
    let(:known_server) do
      { "access_policy"   => "open access, please send a message to notify",
        "address"         => "tick.nap.com.ar",
        "country"         => "AR",
        "exact_location"  => "Network Access Point, Buenos Aires, Argentina",
        "location"        => "Argentina",
        "stratum"         => "2",
        "synchronization" => "NTP V3 secondary (stratum 2), Cisco IOS" }
    end
    let(:country_server) do
      { "address" => "ca.pool.ntp.org", "country" => "CA", "location" => "Canada" }
    end

    it "initializes ntp_servers as an empty hash" do
      allow(subject).to receive(:read_known_servers).and_return([])
      allow(subject).to receive(:pool_servers_for).with(anything).and_return([])

      subject.send(:update_ntp_servers!)

      expect(subject.instance_variable_get(:@ntp_servers)).to eql({})
    end

    it "adds known servers to ntp_servers" do
      allow(subject).to receive(:pool_servers_for).with(anything).and_return([])
      allow(subject).to receive(:cache_server).with(anything)
      expect(subject).to receive(:read_known_servers).and_call_original
      expect(subject).to receive(:cache_server).with(known_server)

      subject.send(:update_ntp_servers!)

    end

    it "adds ntp pool servers for known countries to ntp_servers" do
      allow(subject).to receive(:read_known_servers).and_return([])
      allow(subject).to receive(:cache_server).with(anything)
      expect(subject).to receive(:pool_servers_for).with(anything).and_call_original
      expect(subject).to receive(:cache_server).with(country_server)

      subject.send(:update_ntp_servers!)
    end
  end
end
