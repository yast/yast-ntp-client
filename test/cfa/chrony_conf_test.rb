require_relative "../test_helper"
require "cfa/memory_file"
require "cfa/chrony_conf"

def ntp_disk_content
  path = File.expand_path("../../fixtures/cfa/chrony.conf.original", __FILE__)
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
end
