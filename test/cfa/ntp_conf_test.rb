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

  describe "#load" do
    context "when there is only one entry of a collection" do
      let(:content) do
        "server 127.127.1.0\n"
      end

      it "fixes the key of the collection" do
        expect(ntp.records.first.augeas[:key]).to eq("server[]")
      end
    end
  end

  describe "#records" do
    let(:content) { ntp_disk_file }

    it "obtains the corrent amount of records" do
      expect(ntp.records.count).to eq(12)
    end

    it "obtains a collection of records" do
      expect(ntp.records).to be_a(CFA::NtpConf::RecordCollection)
    end
  end
end

describe CFA::NtpConf::RecordCollection do
  subject(:ntp) { CFA::NtpConf.new(file_handler: ntp_file) }

  let(:ntp_file) { CFA::MemoryFile.new(ntp_disk_file) }

  let(:new_record) do
    record = CFA::NtpConf::ServerRecord.new
    record.value = "4.pool.ntp.org"
    record
  end

  let(:existing_record) { ntp.records.first.dup }

  before do
    ntp.load
  end

  context "#add" do
    context "when does not exist the record to add" do
      it "adds the record" do
        ntp.records.add(new_record)
        expect(ntp.records.include?(new_record)).to be(true)
      end
    end

    context "when exists the record to add" do
      it "adds the record too" do
        ntp.records.add(existing_record)
        expect(ntp.records.count(existing_record)).to eq(2)
      end
    end
  end

  context "#delete" do
    context "when does not exist the record to delete" do
      it "does anything" do
        records = ntp.records
        ntp.records.delete(new_record)
        expect(ntp.records).to eq(records)
      end
    end

    context "when exists the record to delete" do
      it "deletes the record" do
        ntp.records.delete(existing_record)
        expect(ntp.records.include?(existing_record)).to be(false)
      end
    end
  end

  context "#delete_if" do
    it "deletes all records that satisfy the condition" do
      ntp.records.delete_if { |record| record.type == "server" }
      expect(ntp.records.any? { |record| record.type == "server" }).to eq(false)
    end
  end
end

describe CFA::NtpConf::Record do
  let(:augeas_options) do
    tree = CFA::AugeasTree.new
    tree.add("iburst", nil)
    tree
  end

  let(:augeas_tree_value) do
    CFA::AugeasTreeValue.new(augeas_options, "4.pool.ntp.org")
  end

  let(:augeas_element) do
    {
      key:   "server[]",
      value: augeas_tree_value
    }
  end

  subject(:record) { described_class.new_from_augeas(augeas_element) }

  describe ".new_from_augeas" do
    it "creates a record of the correct class" do
      expect(record).to be_a(CFA::NtpConf::ServerRecord)
    end

    it "creates the record with correct data" do
      expect(record.augeas).to eq(augeas_element)
    end
  end

  describe "#value" do
    it "obtains the value of the record" do
      expect(record.value).to eq(augeas_element[:value].value)
    end
  end

  describe "#value=" do
    it "sets the value of the record" do
      value = "1.pool.ntp.org"
      record.value = value
      expect(record.value).to eq(value)
    end
  end

  describe "#comment" do
    context "when the record has not comment" do
      it "obtains nil" do
        expect(record.comment).to eq(nil)
      end
    end

    context "when the record has comment" do
      let(:augeas_options) do
        tree = CFA::AugeasTree.new
        tree.add("#comment", "sample comment")
        tree
      end

      it "obtains the comment" do
        expect(record.comment).to eq("sample comment")
      end
    end
  end

  describe "#comment=" do
    it "sets a comment to the record" do
      comment = "sample comment"
      record.comment = comment
      expect(record.comment).to eq(comment)
    end
  end

  describe "#==" do
    it "returns true for equal records" do
      equal_record = described_class.new_from_augeas(augeas_element)
      expect(record == equal_record).to be(true)
    end

    it "returns false for different records" do
      different_record = CFA::NtpConf::Record.new(key: "server[]")
      different_record.value = "10.10.10.10"
      expect(record == different_record).to be(false)
    end
  end

  describe "#type" do
    it "obtains the type of the record" do
      expect(record.type).to eq("server")
    end
  end

  describe "#raw_options" do
    it "obtains options as string" do
      expect(record.raw_options).to eq("iburst")
    end
  end

  describe "#raw_options=" do
    it "sets options from a string" do
      record.raw_options = "iburst prefer"
      expect(record.options).to eq(["iburst", "prefer"])
    end
  end
end

describe CFA::NtpConf::CommandRecord do
  let(:augeas_element) do
    tree = CFA::AugeasTree.new
    tree.add("iburst", nil)
    value = CFA::AugeasTreeValue.new(tree, "4.pool.ntp.org")
    { key: "server[]", value: value }
  end

  subject(:record) { described_class.new_from_augeas(augeas_element) }

  describe "#options" do
    it "obtains the options of the record" do
      expect(record.options).to eq(["iburst"])
    end
  end

  describe "#options=" do
    it "sets options to the record" do
      record.options = ["iburst", "prefer"]
      expect(record.options).to eq(["iburst", "prefer"])
    end
  end
end

describe CFA::NtpConf::FudgeRecord do
  let(:augeas_element) do
    tree = CFA::AugeasTree.new
    tree.add("stratum", "10")
    value = CFA::AugeasTreeValue.new(tree, "127.127.1.0")
    { key: "fudge[]", value: value }
  end

  subject(:record) { described_class.new_from_augeas(augeas_element) }

  describe "#options" do
    it "obtains the options of the record" do
      expect(record.options).to eq("stratum" => "10")
    end
  end

  context "#options=" do
    it "sets options to the record" do
      options = { "stratum" => "11" }
      record.options = options
      expect(record.options).to eq(options)
    end
  end

  describe "#raw_options" do
    it "obtains options as string" do
      expect(record.raw_options).to eq("stratum 10")
    end
  end

  describe "#raw_options=" do
    it "sets options from a string" do
      record.raw_options = "stratum 11"
      expect(record.options).to eq("stratum" => "11")
    end
  end
end

describe CFA::NtpConf::RestrictRecord do
  let(:augeas_element) do
    tree = CFA::AugeasTree.new
    tree.add("action[]", "default")
    value = CFA::AugeasTreeValue.new(tree, "127.127.1.0")
    { key: "restrict[]", value: value }
  end

  subject(:record) { described_class.new_from_augeas(augeas_element) }

  describe "#options" do
    it "obtains the options of the record" do
      expect(record.options).to eq(["default"])
    end
  end

  context "#options=" do
    it "sets options to the record" do
      options = ["default", "notrap"]
      record.options = options
      expect(record.options).to eq(options)
    end
  end

  describe "#raw_options" do
    it "obtains options as string" do
      expect(record.raw_options).to eq("default")
    end
  end

  describe "#raw_options=" do
    it "sets options from a string" do
      record.raw_options = "default notrap"
      expect(record.options).to eq(["default", "notrap"])
    end
  end
end
