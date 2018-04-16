require_relative "test_helper"

require "yast2/target_file"
require "fileutils"
require "cfa/memory_file"
require "cfa/ntp_conf"

Yast.import "NtpClient"
Yast.import "NetworkInterfaces"
Yast.import "PackageSystem"
Yast.import "Service"
Yast.import "Profile"

describe Yast::NtpClient do

  subject do
    cl = Yast::NtpClientClass.new
    cl.main
    cl
  end

  let(:data_dir) { File.join(File.dirname(__FILE__), "data") }

  around do |example|
    ::FileUtils.cp(File.join(data_dir, "scr_root/etc/ntp.conf.original"),
      File.join(data_dir, "scr_root/etc/ntp.conf"))
    change_scr_root(File.join(data_dir, "scr_root"), &example)
    ::FileUtils.rm(File.join(data_dir, "scr_root/etc/ntp.conf"))
  end

  describe "#AutoYaST methods" do
    FIXTURES_PATH = File.join(File.dirname(__FILE__), "fixtures")

    let(:ntp_client_section) do
      # Yast Profile respect changed SCR, but xmlagent not, so it crashed in
      # changed SCR root, so reset it back for this part
      reset_scr_root
      file = File.join(FIXTURES_PATH, "autoyast", profile_name)
      Yast::Profile.ReadXML(file)
      profile = Yast::Profile.current["ntp-client"]
      change_scr_root(File.join(data_dir, "scr_root"))

      profile
    end

    describe "#Import" do
      context "with a correct AutoYaST configuration file" do
        let(:profile_name) { "autoinst.xml" }

        before(:each) do
          subject.Import(ntp_client_section)
        end

        it "sanitizes values" do
          record = subject.ntp_records.first
          expect(record["address"]).to eq "0.opensuse.pool.ntp.org"
        end

        it "sanitizes comments by removing blank spaces at the beginning and adding line break" do
          record = subject.ntp_records.first
          expect(record["comment"]).to eq "# a comment with spaces \n"
        end

        it "reads the list of peers" do
          expect(subject.ntp_records.size).to eq 5
        end

        it "reads the list of restricts" do
          expect(subject.restrict_map.keys).to contain_exactly(
            "default", "127.0.0.1", "::1"
          )
        end

        it "reads synchronize flag" do
          expect(subject.synchronize_time).to eq true
        end

        it "reads start at boot flag" do
          expect(subject.run_service).to eq true
        end

        it "reads start in chroot environment flag" do
          expect(subject.run_chroot).to eq false
        end

        it "reads policy" do
          expect(subject.ntp_policy).to eq "STATIC"
        end

        it "reads sync intervall" do
          expect(subject.sync_interval).to eq 15
        end

        it "following write succeed" do
          puts subject.ntp_records.inspect
          expect(Yast::Report).to_not receive(:Error)
          expect(subject.Write).to eq true
        end
      end

      context "with an empty AutoYaST configuration" do
        let(:ntp_client_section) { {} }

        before(:each) do
          subject.Import(ntp_client_section)
        end

        it "sets an empty peer list" do
          expect(subject.ntp_records).to be_empty
        end

        it "sets an empty restricts list" do
          expect(subject.restrict_map).to be_empty
        end

        it "sets default synchronize flag" do
          expect(subject.synchronize_time).to eq false
        end

        it "sets default start at boot flag" do
          expect(subject.run_service).to eq false
        end

        it "sets default start in chroot environment flag" do
          expect(subject.run_chroot).to eq true
        end

        it "sets default policy" do
          expect(subject.ntp_policy).to eq ""
        end

        it "set default sync intervall" do
          expect(subject.sync_interval).to eq 5
        end
      end
    end

    describe "#Export" do
      let(:profile_name) { "autoinst.xml" }
      let(:ntp_conf) do
        path = File.expand_path("../fixtures/cfa/ntp.conf", __FILE__)
        text = File.read(path)
        file = CFA::MemoryFile.new(text)
        CFA::NtpConf.new(file_handler: file)
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
      allow(subject).to receive(:read_chroot_config!)
      allow(subject).to receive(:read_policy!)
      allow(Yast::SuSEFirewall).to receive(:Read)
      allow(Yast::Service).to receive(:Enabled).with("ntpd").and_return(true)
      allow(Yast::NetworkInterfaces).to receive(:Read)
      allow(Yast::Progress)
      allow(Yast::PackageSystem).to receive(:CheckAndInstallPackagesInteractive)
        .with(["ntp"]).and_return(true)
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
            .with(["ntp"]).and_return(false)
          expect(Yast::Service).not_to receive(:Enabled)

          expect(subject.Read).to eql(false)
        end
      end

      it "checks if ntpd service is enable" do
        expect(Yast::Service).to receive(:Enabled).with("ntpd")

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

      it "reads ntpd chroot config" do
        expect(subject).to receive(:read_chroot_config!)

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
      allow(subject).to receive(:write_chroot_config)
      allow(subject).to receive(:check_service)

      allow(Yast::SuSEFirewall)
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

      # don't shoot messenger, this API is horrible and I just test it
      subject.selectSyncRecord(-1)
      subject.selected_record["type"] = "server"
      subject.selected_record["options"] = "iburst"
      subject.selected_record["address"] = "tik.cesnet.cz"
      subject.storeSyncRecord

      expect(subject.Write).to eq true
      lines = File.read(File.join(data_dir, "scr_root/etc/ntp.conf"))
      expect(lines.lines).to include("server tik.cesnet.cz iburst\n")
    end

    it "does not write removed records to ntp config" do
      expect(subject).to receive(:write_ntp_conf).and_call_original
      expect(Yast::Report).to_not receive(:Error)
      subject.ProcessNtpConf

      index_to_delete = subject.ntp_records.index { |r| r["address"] == "3.pool.ntp.org" }
      expect(index_to_delete).to_not eq nil
      subject.deleteSyncRecord(index_to_delete)

      expect(subject.Write).to eq true
      lines = File.read(File.join(data_dir, "scr_root/etc/ntp.conf"))
      expect(lines.lines).to_not include("server 3.pool.ntp.org\n")
      expect(lines.lines).to include("server 0.pool.ntp.org\n")
      expect(lines.lines).to include("server 1.pool.ntp.org\n")
      expect(lines.lines).to include("server 2.pool.ntp.org\n")
    end

    it "writes ntp policy and updates ntp with netconfig" do
      expect(subject).to receive(:write_and_update_policy)

      subject.Write
    end

    it "writes chroot ntp config" do
      expect(subject).to receive(:write_chroot_config)

      subject.Write
    end

    it "calls SuSEFirewall.Write to check pending changes" do
      expect(Yast::SuSEFirewall).to receive(:Write)
      subject.Write
    end

    it "checks ntp service" do
      expect(subject).to receive(:check_service)

      subject.Write
    end

    it "updates cron settings" do
      expect(subject).to receive(:update_cron_settings)

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

  describe "#IsRandomServersServiceEnabled" do
    it "returns true if all random pool ntp servers are in use" do
      expect(subject).to receive(:GetUsedNtpServers)
        .and_return(Yast::NtpClientClass::RANDOM_POOL_NTP_SERVERS)

      expect(subject.IsRandomServersServiceEnabled).to eql(true)
    end
    it "returns false in other case" do
      expect(subject).to receive(:GetUsedNtpServers)
        .and_return(["0.pool.ntp.org", "ntp.suse.de", "de.pool.ntp.org"])

      expect(subject.IsRandomServersServiceEnabled).to eql(false)
    end
  end

  describe "#DeActivateRandomPoolServersFunction" do
    it "removes random pool ntp servers from @ntp_records" do
      load_records

      expect(subject.GetUsedNtpServers.size).to eql(4)
      expect(subject.GetUsedNtpServers).to include "0.pool.ntp.org"
      subject.DeActivateRandomPoolServersFunction
      expect(subject.GetUsedNtpServers.size).to eql(1)
      expect(subject.GetUsedNtpServers).not_to include "0.pool.ntp.org"
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
    let(:cron_job_file) { "/etc/cron.d/novell.ntp-synchronize" }
    let(:cron_entry) { [] }

    before do
      allow(Yast::SCR).to receive(:Read)
        .with(Yast::Path.new(".cron"), cron_job_file, "").and_return(cron_entry)
    end

    it "reads cron file" do
      expect(Yast::SCR).to receive(:Read)
        .with(Yast::Path.new(".cron"), cron_job_file, "")

      subject.ReadSynchronization
    end

    context "when cron file does not exist" do
      let(:cron_entry) { nil }

      it "sets synchronize_time as false" do
        subject.ReadSynchronization

        expect(subject.synchronize_time).to eql(false)
      end

      it "sets sync interval with default value" do
        subject.ReadSynchronization

        expect(subject.sync_interval).to eql(Yast::NtpClientClass::DEFAULT_SYNC_INTERVAL)
      end
    end

    context "when cron file exists" do
      context "when there is no cron entry" do
        it "sets synchronize_time as false" do
          subject.ReadSynchronization

          expect(subject.synchronize_time).to eql(false)
        end

        it "sets sync interval with default value" do
          subject.ReadSynchronization

          expect(subject.sync_interval).to eql(Yast::NtpClientClass::DEFAULT_SYNC_INTERVAL)
        end
      end

      context "when there is cron entry" do
        let(:cron_entry) { [{ "events"   => [{ "active" => "1", "minute" => "*/10" }] }] }

        it "sets synchronize time as true if first cron entry is valid" do
          expect(subject.ReadSynchronization).to eql(true)
        end

        it "sets sync_interval with cron minute interval" do
          subject.ReadSynchronization

          expect(subject.sync_interval).to eql(10)
        end
      end
    end
  end

  describe "#reachable_ntp_server?" do
    context "given a server" do
      it "returns true if sntp test passed with IPv4" do
        expect(subject).to receive(:sntp_test).with("server").and_return(true)
        expect(subject).not_to receive(:sntp_test).with("server", 6)

        expect(subject.reachable_ntp_server?("server")).to eql(true)
      end

      it "returns true if sntp test passed with IPv6" do
        expect(subject).to receive(:sntp_test).with("server").and_return(false)
        expect(subject).to receive(:sntp_test).with("server", 6).and_return(true)

        expect(subject.reachable_ntp_server?("server")).to eql(true)
      end

      it "returns false if sntp test fails with IPv4 and with IPv6" do
        expect(subject).to receive(:sntp_test).with("server").and_return(false)
        expect(subject).to receive(:sntp_test).with("server", 6).and_return(false)

        expect(subject.reachable_ntp_server?("server")).to eql(false)
      end
    end
  end

  describe "#sntp_test" do
    let(:ip_version) { 4 }
    let(:server) { "sntp.server.de" }
    let(:output) { { "stdout" => "", "stderr" => "", "exit" => 0 } }

    it "calls sntp command with ip version 4 by default" do
      expect(Yast::SCR).to receive(:Execute)
        .with(Yast::Path.new(".target.bash_output"),
          "LANG=C /usr/sbin/sntp -#{ip_version} -K /dev/null -t 5 -c #{server}")
        .and_return(output)

      subject.sntp_test(server)
    end

    it "returns false if server is not reachable" do
      output["stderr"] = "server_name lookup error Name or service not known"
      expect(Yast::SCR).to receive(:Execute)
        .with(path(".target.bash_output"),
          "LANG=C /usr/sbin/sntp -#{ip_version} -K /dev/null -t 5 -c #{server}")
        .and_return(output)

      expect(subject.sntp_test(server)).to eql(false)
    end

    it "returns false if sntp response includes 'no UCST'" do
      output["stdout"] = "sntp 4.2.8p8@1.3265-o Fri Sep 30 15:52:10 UTC 2016 (1)\n" \
        "195.113.144.2 no UCST response after 5 seconds\n"
      expect(Yast::SCR).to receive(:Execute)
        .with(path(".target.bash_output"),
          "LANG=C /usr/sbin/sntp -#{ip_version} -K /dev/null -t 5 -c #{server}")
        .and_return(output)

      expect(subject.sntp_test(server)).to eql(false)
    end

    it "returns true if sntp command's exit code is 0" do
      output["stdout"] = "sntp 4.2.8p8@1.3265-o Fri Sep 30 15:52:10 UTC 2016 (1)\n"
      expect(Yast::SCR).to receive(:Execute)
        .with(path(".target.bash_output"),
          "LANG=C /usr/sbin/sntp -#{ip_version} -K /dev/null -t 5 -c #{server}")
        .and_return(output)

      expect(subject.sntp_test(server)).to eql(true)
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
      ["0.pool.ntp.org", "1.pool.ntp.org", "2.pool.ntp.org", "3.pool.ntp.org"]
    end

    it "returns a list of NTP servers used in the current configuration" do
      load_records

      expect(subject.GetUsedNtpServers).to eql(used_ntp_servers)
    end
  end

  describe "#getSyncRecords" do

    it "returns a map's list with current synchronization related entries with index" do
      load_records

      expect(subject.getSyncRecords.size).to eql(6)
      expect(subject.getSyncRecords[3]["address"]).to eql("3.pool.ntp.org")
      expect(subject.getSyncRecords[5]["address"]).to eql("192.168.1.30")
    end
  end

  describe "#selectSyncRecord" do
    before do
      load_records
    end

    context "when given index is not between -1 an ntp_records size" do
      it "returns false" do
        expect(subject.selectSyncRecord(-2)).to eql(false)
        expect(subject.selectSyncRecord(21)).to eql(false)
      end

      it "sets selected_index as -1" do
        subject.selectSyncRecord(-2)

        expect(subject.selected_index).to eql(-1)
      end

      it "sets selected_record as an empty hash" do
        subject.selectSyncRecord(-2)

        expect(subject.selected_record).to eql({})
      end
    end

    context "when given index is -1" do
      it "sets selected_index as -1" do
        subject.selectSyncRecord(-1)

        expect(subject.selected_index).to eql(-1)
      end

      it "sets selected_record as an empty hash" do
        subject.selectSyncRecord(-1)

        expect(subject.selected_record).to eql({})
      end

      it "returns true" do
        expect(subject.selectSyncRecord(-1)).to eql(true)
      end
    end

    context "when given index is between 0 and ntp_records size" do
      let(:selected_record) do
        { "type" => "server", "address" => "3.pool.ntp.org", "options" => "", "comment" => "" }
      end

      it "sets selected_index as given value" do
        subject.selectSyncRecord(3)
        expect(subject.selected_index).to eql(3)
      end

      it "sets selected_record as the ntp_records entry for given index" do
        subject.selectSyncRecord(9)
        record = subject.selected_record.reject { |k| k == "cfa_record" }
        expect(record).to eql(selected_record)
      end

      it "returns true" do
        expect(subject.selectSyncRecord(0)).to eql(true)
      end
    end
  end

  describe "#deleteSyncRecord" do
    let(:deleted_record) do
      { "type" => "server", "address" => "0.pool.ntp.org", "options" => "", "comment" => "" }
    end

    before do
      load_records
    end

    it "returns false if given index is not in @ntp_records size range" do
      expect(subject.deleteSyncRecord(-1)).to eql(false)
      expect(subject.deleteSyncRecord(20)).to eql(false)
    end

    it "returns true otherwise" do
      expect(subject.deleteSyncRecord(3)).to eql(true)
    end

    it "sets modified as true if deleted record" do
      subject.modified = false
      subject.deleteSyncRecord(3)
      expect(subject.modified).to eql(true)
    end

    it "removes record entry from ntp records at given index position" do
      old_size = subject.ntp_records.size
      expect(subject.deleteSyncRecord(0)).to eql(true)

      subject.selectSyncRecord(0)
      record = subject.selected_record.reject { |k| k == "cfa_record" }
      expect(record).not_to eql(deleted_record)
      expect(subject.ntp_records.size).to eql(old_size - 1)
    end
  end

  describe "#ProcessNtpConf" do
    it "returns false if config has been read previously" do
      subject.instance_variable_set(:@config_has_been_read, true)
      expect(subject.ProcessNtpConf).to eql(false)
    end

    it "returns false if config doesn't exist" do
      allow(Yast::FileUtils).to receive(:Exists).with("/etc/ntp.conf").and_return(false)
      expect(subject.ProcessNtpConf).to eql(false)
    end

    it "sets configuration as read and returns true" do
      expect(subject.ProcessNtpConf).to eql(true)
      expect(subject.config_has_been_read).to eql(true)
    end

    # FIXME: Add fudge entries to test
    it "initializes ntp records excluding restrict and fudge entries" do
      subject.ProcessNtpConf
      expect(subject.ntp_records.map { |r| r["type"] }).not_to include("restrict")
    end

    it "initializes restrict records" do
      subject.ProcessNtpConf
      # FIXME: this is in fact wrong, as there are 4 entries, but two have same address
      # and map have address as key
      expect(subject.restrict_map.size).to eql(3)
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

  describe "#read_chroot_config!" do
    it "reads sysconfig NTPD_RUN_CHROOTED variable" do
      expect(Yast::SCR).to receive(:Read)
        .with(path(".sysconfig.ntp.NTPD_RUN_CHROOTED"))

      subject.send(:read_chroot_config!)
    end

    context "when NTPD_RUN_CHROOTED variable doesn't exist" do
      it "returns false" do
        expect(Yast::SCR).to receive(:Read)
          .with(path(".sysconfig.ntp.NTPD_RUN_CHROOTED")).and_return(nil)

        expect(subject.send(:read_chroot_config!)).to eql(false)
      end
    end

    context "when NTPD_RUN_CHROOTED variable exists" do
      it "returns true" do
        expect(Yast::SCR).to receive(:Read)
          .with(path(".sysconfig.ntp.NTPD_RUN_CHROOTED")).and_return("no")

        expect(subject.send(:read_chroot_config!)).to eql(true)
      end

      it "sets ntpd as chrooted if variable is 'yes'" do
        expect(Yast::SCR).to receive(:Read)
          .with(path(".sysconfig.ntp.NTPD_RUN_CHROOTED")).and_return("yes")
        subject.send(:read_chroot_config!)

        expect(subject.run_chroot).to eql(true)
      end

      it "sets ntpd as no chrooted in any other case" do
        expect(Yast::SCR).to receive(:Read)
          .with(path(".sysconfig.ntp.NTPD_RUN_CHROOTED")).and_return("other")

        subject.send(:read_chroot_config!)

        expect(subject.run_chroot).to eql(false)
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
