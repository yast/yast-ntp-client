#! /usr/bin/env rspec

require_relative "test_helper"

require_relative "../src/clients/ntp-client_proposal"

Yast.import "Packages"

describe Yast::NtpClientProposalClient do
  subject do
    client = described_class.new
    client.main
    client
  end

  let(:dhcp_ntp_servers) { [] }

  before do
    allow(Yast::Lan).to receive(:dhcp_ntp_servers)
      .and_return(dhcp_ntp_servers)
  end

  describe "#main" do
    let(:client) { described_class.new }
    let(:func) { "dhcp_ntp_servers" }

    before do
      allow(Yast::WFM).to receive(:Args).with(no_args).and_return([func])
      allow(Yast::WFM).to receive(:Args).with(0).and_return(func)
    end

    context "when call with 'dhcp_ntp_servers' argument" do
      let(:dhcp_ntp_servers) { ["test.example.net", "test2.example.net"] }

      it "returns servers found via DHCP" do
        expect(client.main).to eql(dhcp_ntp_servers)
      end
    end
  end

  describe "#MakeProposal" do
    let(:config_was_read?) { false }
    let(:ntp_was_selected?) { false }

    before do
      allow(Yast::NtpClient).to receive(:country_ntp_servers).with("de")
        .and_return([Y2Network::NtpServer.new("de.pool.ntp.org")])
      allow(Yast::Timezone).to receive(:timezone).and_return("Europe/Berlin")
      allow(Yast::Timezone).to receive(:GetCountryForTimezone)
        .with("Europe/Berlin").and_return("de")
      allow(Yast::NtpClient).to receive(:config_has_been_read).and_return(config_was_read?)
      allow(Yast::NtpClient).to receive(:ntp_selected).and_return(ntp_was_selected?)
      allow(Yast::NtpClient).to receive(:GetUsedNtpServers)
        .and_return(["de.pool.ntp.org"])
      allow(subject).to receive(:select_ntp_server).and_return(true)
      allow(Yast::Stage).to receive(:initial).and_return(true)
      allow(Yast::UI).to receive(:ChangeWidget)
      allow(Y2Network::NtpServer).to receive(:default_servers).and_return({})
    end

    context "when NTP servers were found via DHCP" do
      let(:dhcp_ntp_servers) { ["test.example.net"] }

      it "proposes only the found servers" do
        expect(Yast::UI).to receive(:ChangeWidget).with(Id(:ntp_address), any_args) do |*args|
          items = args.last
          hostnames = items.map { |i| i[1] }
          expect(hostnames).to include "test.example.net"
        end
        subject.MakeProposal
      end
    end

    context "when no NTP server were found via DHCP" do
      let(:dhcp_ntp_servers) { [] }

      it "proposes the known public servers for the current timezone" do
        expect(Yast::UI).to receive(:ChangeWidget).with(Id(:ntp_address), any_args) do |*args|
          items = args.last
          hostnames = items.map { |i| i[1] }
          expect(hostnames).to eq(["de.pool.ntp.org"])
        end
        subject.MakeProposal
      end
    end

    context "when the NTP configuration has been read (from chrony)" do
      let(:config_was_read?) { true }

      it "proposes the known public servers for the current timezone" do
        expect(Yast::UI).to receive(:ChangeWidget).with(Id(:ntp_address), any_args) do |*args|
          items = args.last
          hostnames = items.map { |i| i[1] }
          expect(hostnames).to eq(["de.pool.ntp.org"])
        end
        subject.MakeProposal
      end
    end

    context "when the NTP server was already selected" do
      let(:ntp_was_selected?) { true }

      it "proposes the known public servers for the current timezone" do
        expect(Yast::UI).to receive(:ChangeWidget).with(Id(:ntp_address), any_args) do |*args|
          items = args.last
          hostnames = items.map { |i| i[1] }
          expect(hostnames).to eq(["de.pool.ntp.org"])
        end
        subject.MakeProposal
      end
    end
  end

  describe "#Write" do
    let(:ntp_server) { "fake.pool.ntp.org" }
    let(:write_only) { false }
    let(:ntpdate_only) { false }
    let(:params) do
      {
        "server"       => ntp_server,
        "write_only"   => write_only,
        "ntpdate_only" => ntpdate_only
      }
    end
    let(:ntp_client) { Yast::NtpClient }
    let(:initial_stage) { false }
    let(:network_running) { false }

    before do
      allow(subject).to receive(:WriteNtpSettings)
      allow(Yast::Stage).to receive(:initial).and_return(initial_stage)
      allow(Yast::Package).to receive(:CheckAndInstallPackages)
      allow(Yast::Report).to receive(:Error)
      allow(Yast::NetworkService).to receive(:isNetworkRunning).and_return(network_running)
      allow(Yast::Service).to receive(:Active).with(ntp_client.service_name).and_return(false)
      allow(Yast::NtpClient).to receive(:dhcp_ntp_servers).and_return([])
      allow(Yast::Timezone).to receive(:GetCountryForTimezone).and_return("de")
    end

    context "with a not valid hostname" do
      let(:ntp_server) { "not_valid" }

      it "does not write settings" do
        expect(subject).to_not receive(:WriteNtpSettings)

        subject.Write(params)
      end

      it "returns :invalid_hostname" do
        expect(subject.Write(params)).to eq(:invalid_hostname)
      end
    end

    context "with valid hostname" do
      before do
        allow(subject).to receive(:ValidateSingleServer).and_return(true)
      end

      context "but in 'write_only' mode" do
        let(:write_only) { true }

        it "only writes settings" do
          expect(subject).to receive(:WriteNtpSettings).once
          expect(Yast::Stage).to_not receive(:initial)
          expect(Yast::NetworkService).to_not receive(:isNetworkRunning)

          subject.Write(params)
        end

        it "returns :success" do
          expect(subject.Write(params)).to eq(:success)
        end
      end

      context "but 'run_service' param is not given" do
        it "uses the current value of NtpClient.run_service" do
          ntp_client.run_service = true
          expect(subject).to receive(:WriteNtpSettings).with(anything, anything, true)
          subject.Write({})

          ntp_client.run_service = false
          expect(subject).to receive(:WriteNtpSettings).with(anything, anything, false)
          subject.Write({})
        end
      end

      context "and is in the initial stage" do
        let(:initial_stage) { true }

        it "imports Yast::Packages" do
          allow(Yast).to receive(:import).and_call_original
          expect(Yast).to receive(:import).with("Packages")

          subject.Write(params)
        end

        it "adds the additional package" do
          expect(Yast::Packages).to receive(:addAdditionalPackage)

          subject.Write(params)
        end
      end

      context "and is not in the  initial stage" do
        it "asks user to confirm the package installation" do
          expect(Yast::Package).to receive(:CheckAndInstallPackages)

          subject.Write(params)
        end

        context "but user rejects the package installation" do
          before do
            allow(Yast::Package).to receive(:CheckAndInstallPackages).and_return(false)
          end

          it "reports an error" do
            expect(Yast::Report).to receive(:Error).with(/Synchronization with NTP server is not/)

            subject.Write(params)
          end
        end
      end

      context "and network is not available" do
        it "does not performs the ntp syncronization" do
          expect(Yast::NtpClient).to_not receive(:sync_once)

          subject.Write(params)
        end

        it "returns :success" do
          expect(subject.Write(params)).to eq(:success)
        end
      end

      context "and network is available" do
        let(:network_running) { true }

        it "returns :ntpdate_failed if synchronization fails" do
          allow(Yast::NtpClient).to receive(:sync_once).and_return(1)

          expect(subject.Write(params)).to eq(:ntpdate_failed)
        end

        it "returns :success if synchronization was successfully" do
          allow(Yast::NtpClient).to receive(:sync_once).and_return(0)

          expect(subject.Write(params)).to eq(:success)
        end
      end

      context "and user only wants to synchronize date" do
        let(:ntpdate_only) { true }

        it "does not write settings" do
          expect(subject).to_not receive(:WriteNtpSettings)

          subject.Write(params)
        end

        it "does not try to synchronize if the service is running" do
          allow(Yast::Service).to receive(:Active).with(ntp_client.service_name).and_return(true)
          expect(Yast::NtpClient).to_not receive(:sync_once)

          subject.Write(params)
        end
      end

      context "and user wants to synchronize on boot" do
        it "writes settings only once" do
          expect(subject).to receive(:WriteNtpSettings).once

          subject.Write(params)
        end
      end
    end
  end

  describe "#select_ntp_server" do
    before do
      allow(Yast::Timezone).to receive(:GetCountryForTimezone).and_return("de")
    end

    context "there are already more than one ntp server defined" do
      it "returns false" do
        allow(Yast::NtpClient).to receive(:GetUsedNtpServers).and_return(["n1", "n2"])
        expect(subject.send(:select_ntp_server)).to eq(false)
      end
    end

    context "there is no ntp server defined" do
      it "returns true" do
        allow(Yast::NtpClient).to receive(:GetUsedNtpServers).and_return([])
        expect(subject.send(:select_ntp_server)).to eq(true)
      end
    end

    context "there is ONE ntp server defined" do
      before do
        allow(Yast::NtpClient).to receive(:dhcp_ntp_servers).and_return([])
      end

      context "and defined server is not in the selection list" do
        it "returns false" do
          allow(Yast::NtpClient).to receive(:GetUsedNtpServers).and_return(["not_found"])
          expect(subject.send(:select_ntp_server)).to eq(false)
        end
      end

      context "and defined server is in the selection list" do
        it "returns true" do
          allow(Yast::NtpClient).to receive(:GetNtpServersByCountry).and_return(
            [Item(Id("de.pool.ntp.org"), "de.pool.ntp.org", true)]
          )
          allow(Yast::NtpClient).to receive(:GetUsedNtpServers).and_return(["de.pool.ntp.org"])
          expect(subject.send(:select_ntp_server)).to eq(true)
        end
      end
    end

  end
end
