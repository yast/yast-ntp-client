#! /usr/bin/env rspec

require_relative "test_helper"

require_relative "../src/clients/ntp-client_proposal.rb"

Yast.import "Packages"

describe Yast::NtpClientProposalClient do
  subject do
    client = described_class.new
    client.main
    client
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
      allow(Yast::PackageSystem).to receive(:CheckAndInstallPackages)
      allow(Yast::Report).to receive(:Error)
      allow(Yast::NetworkService).to receive(:isNetworkRunning).and_return(network_running)
      allow(Yast::Service).to receive(:Active).with(ntp_client.service_name).and_return(false)
    end

    context "with a not valid hostname" do
      let(:ntp_server) { nil }

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
          expect(Yast::PackageSystem).to receive(:CheckAndInstallPackages)

          subject.Write(params)
        end

        context "but user rejects the package installation" do
          before do
            allow(Yast::PackageSystem).to receive(:CheckAndInstallPackages).and_return(false)
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
          allow(Yast::NtpClient).to receive(:sync_once).with(ntp_server).and_return(1)

          expect(subject.Write(params)).to eq(:ntpdate_failed)
        end

        it "returns :success if syncronization was successfully" do
          allow(Yast::NtpClient).to receive(:sync_once).with(ntp_server).and_return(0)

          expect(subject.Write(params)).to eq(:success)
        end
      end

      context "and user only wants to syncronize date" do
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

      context "and user wants to syncronize on boot" do
        it "writes settings only once" do
          expect(subject).to receive(:WriteNtpSettings).once

          subject.Write(params)
        end
      end
    end
  end
end
