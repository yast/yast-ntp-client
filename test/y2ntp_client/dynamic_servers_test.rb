#! /usr/bin/env rspec
require_relative "../test_helper"

require "cwm/rspec"
require "y2ntp_client/dynamic_servers"

Yast.import "Lan"
Yast.import "LanItems"

class Dummy
  include Y2NtpClient::DynamicServers
end

describe Y2NtpClient::DynamicServers do
  let(:subject) { Dummy.new }
  let(:servers) do
    {
      "eth0" => ["0.pool.ntp.org", "1.pool.ntp.org"],
      "eth1" => ["2.pool.ntp.org"]
    }
  end

  before do
    allow(Yast::LanItems).to receive(:dhcp_ntp_servers).and_return(servers)
  end

  describe "#dhcp_ntp_servers" do
    it "reads the current network configuration" do
      expect(Yast::Lan).to receive(:ReadWithCacheNoGUI)
      subject.dhcp_ntp_servers
    end

    it "returns a list of the ntp_servers provided by dhcp " do
      expect(Yast::LanItems).to receive(:dhcp_ntp_servers).and_return(servers)
      expect(subject.dhcp_ntp_servers)
        .to eql(["0.pool.ntp.org", "1.pool.ntp.org", "2.pool.ntp.org"])
    end
  end
end
