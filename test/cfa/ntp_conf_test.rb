require_relative "../test_helper"
require "cfa/memory_file"
require "cfa/ntp_conf"

def ntp_disk_content
  path = File.expand_path("../../fixtures/cfa/ntp.conf", __FILE__)
  File.read(path)
end

def ntp_file(content)
  CFA::MemoryFile.new(content)
end

def ntp_conf(file)
  CFA::NtpConf.new(file_handler: file)
end

describe CFA::NtpConf do
  subject(:ntp) { ntp_conf(file) }

  let(:file) { ntp_file(content) }

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
    let(:content) { ntp_disk_content }

    it "obtains the corrent amount of records" do
      expect(ntp.records.count).to eq(12)
    end

    it "obtains a collection of records" do
      expect(ntp.records).to be_a(CFA::NtpConf::RecordCollection)
    end
  end

  describe "#save" do
    let(:content) do
      "server 0.pool.ntp.org\n" \
      "server 1.pool.ntp.org\n" \
      "server 2.pool.ntp.org\n"
    end

    context "when a record is added" do
      it "writes a new entry" do
        record = CFA::NtpConf::ServerRecord.new
        record.value = "3.pool.ntp.org"
        ntp.records << record
        ntp.save
        expect(file.content.lines).to include("server 3.pool.ntp.org\n")
      end

      it "writes it together with its options" do
        record = CFA::NtpConf::ServerRecord.new
        record.value = "3.pool.ntp.org"
        record.raw_options = "iburst dynamic"
        ntp.records << record
        ntp.save
        expect(file.content.lines).to include("server 3.pool.ntp.org iburst dynamic\n")
      end

      it "writes comment from entry" do
        record = CFA::NtpConf::ServerRecord.new
        record.value = "3.pool.ntp.org"
        record.comment = "# test comment"
        ntp.records << record
        ntp.save
        expect(file.content.lines).to include("server 3.pool.ntp.org# test comment\n")

      end
    end

    context "when a record is deleted" do
      it "removes an entry" do
        record = ntp.records.find { |r| r.value == "0.pool.ntp.org" }
        ntp.records.delete(record)
        ntp.save
        expect(file.content.lines).not_to include("server 0.pool.ntp.org\n")
      end
    end

    context "when a record is updated" do
      it "modifies an entry" do
        record = ntp.records.find { |r| r.value == "0.pool.ntp.org" }
        record.value = "10.pool.ntp.org"
        ntp.save
        expect(file.content.lines).not_to include("server 0.pool.ntp.org\n")
        expect(file.content.lines).to include("server 10.pool.ntp.org\n")
      end
    end
  end
end

describe CFA::NtpConf::RecordCollection do
  let(:ntp) { ntp_conf(file) }

  let(:file) { ntp_file(content) }

  let(:new_record) do
    record = CFA::NtpConf::ServerRecord.new
    record.value = "3.pool.ntp.org"
    record
  end

  let(:existing_record) { ntp.records.first }

  let(:content) do
    "server 0.pool.ntp.org\n" \
    "server 1.pool.ntp.org\n" \
    "server 2.pool.ntp.org\n"
  end

  before do
    ntp.load
  end

  context "#<<" do
    context "when does not exist the record to add" do
      it "adds the record" do
        ntp.records << new_record
        expect(ntp.records.count(new_record)).to eq(1)
      end
    end

    context "when exists the record to add" do
      it "adds the record too" do
        ntp.records << existing_record
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
  let(:ntp) { ntp_conf(file) }

  let(:file) { ntp_file(content) }

  let(:content) do
    "server 0.pool.ntp.org iburst\n" \
    "server 1.pool.ntp.org #sample comment\n" \
    "server 2.pool.ntp.org\n"
  end

  before do
    ntp.load
  end

  describe ".new_from_augeas" do
    let(:augeas_element) do
      {
        key:   "server[]",
        value: "3.pool.ntp.org"
      }
    end

    subject(:record) { described_class.new_from_augeas(augeas_element) }

    it "creates a record of the correct class" do
      expect(record).to be_a(CFA::NtpConf::ServerRecord)
    end

    it "creates the record with correct data" do
      expect(record.augeas).to eq(augeas_element)
    end
  end

  describe "#value" do
    it "obtains the value of the record" do
      record = ntp.records.first
      expect(record.value).to eq("0.pool.ntp.org")
    end
  end

  describe "#value=" do
    it "sets the value of the record" do
      value = "3.pool.ntp.org"
      record = ntp.records.first
      record.value = value
      expect(record.value).to eq(value)
      ntp.save
      expect(file.content).to include("server 3.pool.ntp.org iburst\n")
    end
  end

  describe "#comment" do
    context "when the record has not comment" do
      it "obtains nil" do
        record = ntp.records.first
        expect(record.comment).to eq(nil)
      end
    end

    context "when the record has comment" do
      it "obtains the comment" do
        record = ntp.records.to_a[1]
        expect(record.comment).to eq("#sample comment")
      end
    end
  end

  describe "#comment=" do
    it "sets a comment to the record" do
      comment = "#sample comment"
      record = ntp.records.first
      record.comment = comment
      expect(record.comment).to eq(comment)
      ntp.save
      expect(file.content).to include("server 0.pool.ntp.org iburst#sample comment\n")
    end
  end

  describe "#==" do
    it "returns true for equal records" do
      record = ntp.records.first
      expect(record == record.dup).to be(true)
    end

    it "returns false for different records" do
      records = ntp.records.to_a
      expect(records[0] == records[1]).to be(false)
    end
  end

  describe "#type" do
    it "obtains the type of the record" do
      expect(ntp.records.first.type).to eq("server")
    end
  end

  describe "#raw_options" do
    it "obtains options as string" do
      expect(ntp.records.first.raw_options).to eq("iburst")
    end
  end

  describe "#raw_options=" do
    it "sets options from a string" do
      record = ntp.records.first
      record.raw_options = "iburst prefer"
      expect(record.options).to eq(["iburst", "prefer"])
      ntp.save
      expect(file.content).to include("server 0.pool.ntp.org iburst prefer\n")
    end
  end
end

describe CFA::NtpConf::CommandRecord do
  let(:ntp) { ntp_conf(file) }

  let(:file) { ntp_file(content) }

  let(:content) do
    "server 0.pool.ntp.org iburst\n"
  end

  before do
    ntp.load
  end

  subject(:record) { ntp.records.first }

  describe "#options" do
    it "obtains the options of the record" do
      expect(record.options).to eq(["iburst"])
    end
  end

  describe "#options=" do
    it "sets options to the record" do
      record.options = ["iburst", "prefer"]
      expect(record.options).to eq(["iburst", "prefer"])
      ntp.save
      expect(file.content).to include("server 0.pool.ntp.org iburst prefer\n")
    end
  end
end

describe CFA::NtpConf::FudgeRecord do
  let(:ntp) { ntp_conf(file) }

  let(:file) { ntp_file(content) }

  let(:content) do
    "fudge 127.127.1.0 stratum 10\n"
  end

  before do
    ntp.load
  end

  subject(:record) { ntp.records.first }

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
      ntp.save
      expect(file.content).to include("fudge 127.127.1.0 stratum 11\n")
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
      ntp.save
      expect(file.content).to include("fudge 127.127.1.0 stratum 11\n")
    end
  end
end

describe CFA::NtpConf::RestrictRecord do
  let(:ntp) { ntp_conf(file) }

  let(:file) { ntp_file(content) }

  let(:content) do
    "restrict -4 default notrap nomodify nopeer\n"
  end

  before do
    ntp.load
  end

  subject(:record) { ntp.records.first }

  describe "#options" do
    it "obtains the options of the record" do
      expect(record.options).to eq(%w(notrap nomodify nopeer))
    end
  end

  context "#options=" do
    it "sets options to the record" do
      options = ["notrap"]
      record.options = options
      expect(record.options).to eq(options)
      ntp.save
      expect(file.content).to include("restrict -4 default notrap\n")
    end
  end

  describe "#raw_options" do
    it "obtains options as string" do
      expect(record.raw_options).to eq("notrap nomodify nopeer")
    end
  end

  describe "#raw_options=" do
    it "sets options from a string" do
      record.raw_options = "notrap"
      expect(record.options).to eq(["notrap"])
      ntp.save
      expect(file.content).to include("restrict -4 default notrap\n")
    end
  end
end
