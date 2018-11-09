require "yast"

module Y2NtpClient
  # Bunch of methods for retrieving ntp servers dinamically, i.e. by dhcp or
  # slp.
  module DynamicServers
    def dhcp_ntp_servers
      Yast.import "Lan"
      Yast.import "LanItems"
      Yast.import "NetworkService"

      # When proposing NTP servers we need to know
      # 1) list of (dhcp) interfaces
      # 2) network service in use
      # We can either use networking submodule for network service handling and get list of
      # interfaces e.g. using a bash command or initialize whole networking module.
      Yast::Lan.ReadWithCacheNoGUI

      Yast::LanItems.dhcp_ntp_servers.values.reduce(&:concat) || []
    end
  end
end
