require_relative "../../test_helper"

require "y2ntp_client/client/auto"

describe Y2NtpClient::Client::Auto do
  let(:data_dir) { File.join(File.dirname(__FILE__), "../../data") }

  around do |example|
    ::FileUtils.cp(File.join(data_dir, "scr_root/etc/chrony.conf.original"),
      File.join(data_dir, "scr_root/etc/chrony.conf"))
    change_scr_root(File.join(data_dir, "scr_root"), &example)
    ::FileUtils.rm(File.join(data_dir, "scr_root/etc/chrony.conf"))
  end

  before do
    allow(Yast::Service).to receive(:Enabled).with("chronyd").and_return(true)
    allow(Yast::Package).to receive(:CheckAndInstallPackagesInteractive)
      .with(["chrony"]).and_return(true)
    Yast::NtpClient.Read
  end

  describe "#summary" do
    it "returns string" do
      expect(subject.summary).to be_a(::String)
    end
  end

  describe "#import" do
    it "pass its arguments to NtpClient.Import" do
      arguments = { "ntp_policy" => "auto" }
      expect(Yast::NtpClient).to receive(:Import).with(arguments)
      subject.import(arguments)
    end

    it "returns true if import success" do
      allow(Yast::NtpClient).to receive(:Import).and_return(true)
      expect(subject.import({})).to eq true
    end

    it "returns false if import failed" do
      allow(Yast::NtpClient).to receive(:Import).and_return(false)
      expect(subject.import({})).to eq false
    end
  end

  describe "#export" do
    it "returns hash with options" do
      expect(subject.export).to be_a(::Hash)
    end
  end

  describe "#reset" do
    it "import empty hash to set defaults" do
      expect(Yast::NtpClient).to receive(:Import).with({})
      subject.reset
    end
  end

  describe "#change" do
    it "opens main dialog" do
      expect(Y2NtpClient::Dialog::Main).to receive(:run)
      subject.change
    end
  end

  describe "#write" do
    before do
      allow(Yast::NtpClient).to receive(:Write)
    end

    it "calls NtpClient write" do
      expect(Yast::NtpClient).to receive(:Write)
      subject.write
    end

    it "disables progress" do
      expect(Yast::Progress).to receive(:set).with(false).and_return(false).twice
      subject.write
    end
  end

  describe "#read" do
    before do
      allow(Yast::NtpClient).to receive(:Read)
    end

    it "calls NtpClient read" do
      expect(Yast::NtpClient).to receive(:Read)
      subject.read
    end

    it "disables progress" do
      expect(Yast::Progress).to receive(:set).with(false).and_return(false).twice
      subject.read
    end
  end

  describe "#packages" do
    it "returns hash with \"install\" and \"remove\" lists of packagesn" do
      expect(subject.packages["install"]).to be_a(::Array)
      expect(subject.packages["remove"]).to be_a(::Array)
    end
  end

  describe "#modified?" do
    it "returns value of NtpClient modified" do
      Yast::NtpClient.modified = true
      expect(subject.modified?).to eq true
    end
  end

  describe "#modified" do
    it "sets value of NtpClient modified to true" do
      Yast::NtpClient.modified = false
      subject.modified
      expect(Yast::NtpClient.modified).to eq true
    end
  end
end
