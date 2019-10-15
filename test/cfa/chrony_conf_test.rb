require_relative "../test_helper"
require "cfa/memory_file"
require "cfa/chrony_conf"

def ntp_disk_content
  path = File.expand_path("../fixtures/cfa/chrony.conf.original", __dir__)
  File.read(path)
end

def ntp_file(content)
  CFA::MemoryFile.new(content)
end

def ntp_conf(file)
  CFA::ChronyConf.new(file_handler: file)
end

describe CFA::ChronyConf do
  subject(:chrony) { ntp_conf(file) }

  let(:file) { ntp_file(content) }

  let(:content) { "" }

  before do
    subject.load
  end

  describe "#clear_pools" do
    let(:content) do
      "pool 2.opensuse.pool.ntp.org iburst\npool pool.ntp.org offline\n"
    end

    it "removes all pools from file" do
      subject.clear_pools
      subject.save
      expect(file.content).to_not match(/pool/)
    end
  end

  describe "#add_pool" do
    context "there is already pool" do
      let(:content) do
        "# Use public servers from the pool.ntp.org project.\n"\
        "# Please consider joining the pool (http://www.pool.ntp.org/join.html).\n" \
        "pool 2.opensuse.pool.ntp.org iburst\n"\
        "rtcsync\n"
      end

      let(:expected_output) do
        "# Use public servers from the pool.ntp.org project.\n"\
        "# Please consider joining the pool (http://www.pool.ntp.org/join.html).\n" \
        "pool 2.opensuse.pool.ntp.org iburst\n"\
        "pool ntp.suse.cz offline\n"\
        "rtcsync\n"
      end

      it "adds new pool after the latest pool entry" do
        subject.add_pool("ntp.suse.cz", "offline" => nil)
        subject.save
        expect(file.content).to eq expected_output
      end
    end

    context "there is pool comments" do
      let(:content) do
        "# Use public servers from the pool.ntp.org project.\n"\
        "# Please consider joining the pool (http://www.pool.ntp.org/join.html).\n" \
        "rtcsync\n"
      end

      let(:expected_output) do
        "# Use public servers from the pool.ntp.org project.\n"\
        "# Please consider joining the pool (http://www.pool.ntp.org/join.html).\n" \
        "pool ntp.suse.cz offline\n"\
        "rtcsync\n"
      end

      it "adds new pool after the comment" do
        subject.add_pool("ntp.suse.cz", "offline" => nil)
        subject.save
        expect(file.content).to eq expected_output
      end
    end

    context "otherwise" do
      let(:content) do
        "rtcsync\n"
      end

      let(:expected_output) do
        "rtcsync\n" \
        "pool ntp.suse.cz offline\n"
      end

      it "adds new pool at the end" do
        subject.add_pool("ntp.suse.cz", "offline" => nil)
        subject.save
        expect(file.content).to eq expected_output
      end
    end
  end

  describe "#hardware_clock?" do
    context "hardware clock defined" do
      let(:content) do
        "refclock PPS /dev/pps0 lock NMEA refid GPS\n"
      end

      it "return true" do
        expect(subject.hardware_clock?).to eq true
      end
    end

    context "no hardware clock defined" do
      let(:content) do
        "rtcsync\n" \
        "pool ntp.suse.cz offline\n"
      end

      it "return true" do
        expect(subject.hardware_clock?).to eq false
      end
    end
  end

  describe "#modify_pool" do
    let(:content) do
      "pool test.ntp.org iburst\n"
    end

    it "sets new address for original address" do
      subject.modify_pool("test.ntp.org", "lest.ntp.org", {})
      subject.save

      expect(file.content.lines).to include "pool lest.ntp.org\n"
    end

    it "modifies options according to passed ones" do
      subject.modify_pool("test.ntp.org", "lest.ntp.org", "offline" => nil, "maxsources" => "5")
      subject.save

      expect(file.content.lines).to include "pool lest.ntp.org offline maxsources 5\n"
    end

    it "works when address does not change" do
      subject.modify_pool("test.ntp.org", "test.ntp.org", {})
      subject.save

      expect(file.content.lines).to include "pool test.ntp.org\n"
    end

    it "appends new pool entry if original address does not exist" do
      subject.modify_pool("lest.ntp.org", "lest.ntp.org", {})
      subject.save

      expect(file.content.lines).to eq ["pool test.ntp.org iburst\n", "pool lest.ntp.org\n"]
    end
  end

  describe "#delete_pool" do
    let(:content) do
      "pool test.ntp.org iburst\n" \
      "pool lest.ntp.org offline\n"
    end

    it "deletes pool entry with given address" do
      subject.delete_pool("lest.ntp.org")
      subject.save

      expect(file.content.lines).to eq ["pool test.ntp.org iburst\n"]
    end

    it "does nothing if pool entry with given address does not exist" do
      subject.delete_pool("not.exist.ntp.org")
      subject.save

      expect(file.content.lines).to eq ["pool test.ntp.org iburst\n", "pool lest.ntp.org offline\n"]
    end
  end

  describe "#default_pool_options" do
    it "returns Hash of default options for pool" do
      expect(subject.default_pool_options).to be_a(Hash)
    end
  end

  describe "#pools" do
    let(:content) do
      "pool test.ntp.org iburst\n" \
      "pool lest.ntp.org offline\n" \
      "pool lest2.ntp.org\n" \
      "# fancy comment\n"
    end

    it "returns Hash with address as key and options as value" do
      expect(subject.pools.size).to eq 3
    end
  end
end
