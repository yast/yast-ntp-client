require_relative "../test_helper"
require "cfa/memory_file"
require "cfa/ntp_conf"

def ntp_disk_file
  path = File.expand_path("../../fixtures/cfa/ntp.conf", __FILE__)
  File.read(path)
end

describe CFA::NtpConf do
  subject(:ntp) { described_class.new(file_handler: ntp_file) }

  let(:ntp_file) { CFA::MemoryFile.new(content) }

  before do
    ntp.load
  end

  context "when ask for the collection" do
    context "#servers" do
      context "if ntp conf has several 'server' entries" do
        let(:content) { ntp_disk_file }

        it "obtains a collection of records" do
          expect(ntp.servers).to be_a(CFA::NtpConf::RecordCollection)
        end

        it "obtains the correct amount of records" do
          expect(ntp.servers.count).to eq(4)
        end

        it "obtains records of type ServerRecord" do
          expect(ntp.servers.all? { |s| s.is_a? CFA::NtpConf::ServerRecord }).to eq(true)
        end
      end

      context "if ntp conf has not 'server' entries" do
        let(:content) { "peer 128.100.0.45\npeer 192.168.1.30\n" }

        it "obtains an empty collection" do
          expect(ntp.servers.empty?).to eq(true)
        end
      end
    end

    context "#peers" do
      context "if ntp conf has several 'peer' entries" do
        let(:content) { ntp_disk_file }

        it "obtains a collection of records" do
          expect(ntp.peers).to be_a(CFA::NtpConf::RecordCollection)
        end

        it "obtains the correct amount of records" do
          expect(ntp.peers.count).to eq(2)
        end

        it "obtains records of type PeerRecord" do
          expect(ntp.peers.all? { |s| s.is_a? CFA::NtpConf::PeerRecord }).to eq(true)
        end
      end

      context "if ntp conf has not 'peer' entries" do
        let(:content) { "server 0.pool.ntp.org\nserver 1.pool.ntp.org\n" }

        it "obtains an empty collection" do
          expect(ntp.peers.empty?).to eq(true)
        end
      end
    end

    context "#restricts" do
      context "if ntp conf has several 'restrict' entries" do
        let(:content) { ntp_disk_file }

        it "obtains a collection of records" do
          expect(ntp.restricts).to be_a(CFA::NtpConf::RecordCollection)
        end

        it "obtains the correct amount of records" do
          expect(ntp.restricts.count).to eq(4)
        end

        it "obtains records of type RestrictRecord" do
          expect(ntp.restricts.all? { |s| s.is_a? CFA::NtpConf::RestrictRecord }).to eq(true)
        end
      end

      context "if ntp conf has not 'retrict' entries" do
        let(:content) { "server 0.pool.ntp.org\nserver 1.pool.ntp.org\n" }

        it "obtains an empty collection" do
          expect(ntp.restricts.empty?).to eq(true)
        end
      end
    end
  end

  context "when get an attribute" do
    context "if ntp conf has an entry for the attribute" do
      let(:content) { ntp_disk_file }

      it "obtains a record of type AttributeRecord" do
        expect(ntp.driftfile).to be_a(CFA::NtpConf::AttributeRecord)
      end
    end

    context "if ntp conf has not an entry for the attribute" do
      let(:content) { "server 0.pool.ntp.org\nserver 1.pool.ntp.org\n" }

      it "obtains nil" do
        expect(ntp.driftfile).to eq(nil)
      end
    end
  end

  context "when set an attribute" do
    context "if ntp conf has an entry for the attribute" do
      let(:content) { ntp_disk_file }

      it "updates the record" do
        path = "/etc/ntp.drift"
        record = CFA::NtpConf::AttributeRecord.new(value: path)
        ntp.driftfile = record
        expect(ntp.driftfile.value).to eq(path)
      end
    end

    context "if ntp conf has not an entry for the attribute" do
      let(:content) { "server 0.pool.ntp.org\nserver 1.pool.ntp.org\n" }

      it "creates a record" do
        record = CFA::NtpConf::AttributeRecord.new(value: "/etc/ntp.drift")
        ntp.driftfile = record
        expect(ntp.driftfile).not_to be(nil)
      end
    end
  end

  context "when delete an attribute" do
    context "if ntp conf has an entry for the attribute" do
      let(:content) { ntp_disk_file }

      it "deletes the attribute" do
        ntp.delete_driftfile
        expect(ntp.driftfile).to be(nil)
      end
    end

    context "if ntp conf has not an entry for the attribute" do
      let(:content) { "server 0.pool.ntp.org\nserver 1.pool.ntp.org\n" }

      it "does nothing" do
        ntp.delete_driftfile
        expect(ntp.driftfile).to be(nil)
      end
    end
  end
end

describe CFA::NtpConf::RecordCollection do
  subject(:ntp) { CFA::NtpConf.new(file_handler: ntp_file) }

  let(:ntp_file) { CFA::MemoryFile.new(ntp_disk_file) }

  let(:new_server) { CFA::NtpConf::ServerRecord.new(value: "4.pool.ntp.org") }

  let(:existing_server) { ntp.servers.first.dup }

  before do
    ntp.load
  end

  context "#add" do
    context "when does not exist the record to add" do
      it "adds the record" do
        ntp.servers.add(new_server)
        expect(ntp.servers.include?(new_server)).to be(true)
      end
    end

    context "when exists the record to add" do
      it "adds the record too" do
        ntp.servers.add(existing_server)
        expect(ntp.servers.count(existing_server)).to eq(2)
      end
    end
  end

  context "#delete" do
    context "when does not exist the record to delete" do
      it "does anything" do
        servers = ntp.servers
        ntp.servers.delete(new_server)
        expect(ntp.servers).to eq(servers)
      end
    end

    context "when exists the record to delete" do
      it "deletes the record" do
        ntp.servers.delete(existing_server)
        expect(ntp.servers.include?(existing_server)).to be(false)
      end
    end
  end

  context "#replace" do
    context "when does not exist the record to replace" do
      it "does anything" do
        servers = ntp.servers
        ntp.servers.replace(new_server, new_server)
        expect(ntp.servers).to eq(servers)
      end
    end

    context "when exists the record to replace" do
      it "deletes the old record" do
        ntp.servers.replace(existing_server, new_server)
        expect(ntp.servers.include?(existing_server)).to be(false)
      end

      it "adds the new record at the same position" do
        ntp.servers.replace(existing_server, new_server)
        expect(ntp.servers.first).to eq(new_server)
      end
    end
  end
end

describe CFA::NtpConf::Record do
  let(:augeas) do
    tree = CFA::AugeasTree.new
    tree.add("iburst", nil)
    CFA::AugeasTreeValue.new(tree, "4.pool.ntp.org")
  end

  let(:record) do
    CFA::NtpConf::Record.new(value:     "4.pool.ntp.org",
                             tree_data: [{ key: "iburst", value: nil }])
  end

  let(:record_from_augeas) { CFA::NtpConf::Record.new_from_augeas(augeas) }

  context ".new_from_augeas" do
    it "creates a record" do
      expect(record_from_augeas).to be_a(CFA::NtpConf::Record)
    end

    it "creates the record with correct data" do
      expect(record_from_augeas).to eq(record)
    end
  end

  context "#to_augeas" do
    it "creates an AugeasTreeValue" do
      expect(record.to_augeas).to be_a(CFA::AugeasTreeValue)
    end

    it "creates an augeas with correct value" do
      expect(record.to_augeas.value).to eq(augeas.value)
    end

    it "creates an augeas with correct tree" do
      expect(record.to_augeas.tree).to eq(augeas.tree)
    end
  end
end

describe CFA::NtpConf::AttributeRecord do
  subject(:record) { described_class.new(value: value, comment: comment) }

  let(:value) { "1" }

  let(:comment) { "# is a requestkey" }

  context "#initialize" do
    it "allows to create an attribute with :value and :comment" do
      expect { described_class.new(value: value, comment: comment) }.to_not raise_error
    end
  end

  context "#value" do
    it "obtains the value of the attribute" do
      expect(record.value).to eq(value)
    end
  end

  context "#comment" do
    it "obtains the comment of the attribute" do
      expect(record.comment).to eq(comment)
    end
  end
end

describe CFA::NtpConf::CommandRecord do
  subject(:record) { described_class.new(value: value, options: options, comment: comment) }

  let(:value) { "0.opensuse.pool.ntp.org" }

  let(:options) { ["iburst"] }

  let(:comment) { "# is a server entry" }

  context "#initialize" do
    it "allows to create a command with :value, :options and :comment" do
      expect do
        described_class.new(value: value, options: options, comment: comment)
      end.to_not raise_error
    end
  end

  context "#value" do
    it "obtains the value of the command" do
      expect(record.value).to eq(value)
    end
  end

  context "#options" do
    it "obtains the options of the command" do
      expect(record.options).to eq(options)
    end
  end

  context "#comment" do
    it "obtains the comment of the command" do
      expect(record.comment).to eq(comment)
    end
  end
end

describe CFA::NtpConf::RestrictRecord do
  subject(:record) { described_class.new(value: value, actions: actions, comment: comment) }

  let(:value) { "192.168.123.0" }

  let(:actions) { ["mask", "255.255.255.0", "notrust"] }

  let(:comment) { "# is a restrict entry" }

  context "#initialize" do
    it "allows to create a restrict with :value, :actions and :comment" do
      expect do
        described_class.new(value: value, actions: actions, comment: comment)
      end.to_not raise_error
    end
  end

  context "#value" do
    it "obtains the value of the restrict" do
      expect(record.value).to eq(value)
    end
  end

  context "#actions" do
    it "obtains the actions of the restrict" do
      expect(record.actions).to eq(actions)
    end
  end

  context "#comment" do
    it "obtains the comment of the restrict" do
      expect(record.comment).to eq(comment)
    end
  end
end
