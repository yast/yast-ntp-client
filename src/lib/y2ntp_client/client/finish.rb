# encoding: utf-8

require "yast"
require "installation/finish_client"

Yast.import "NtpClient"

module Y2NtpClient
  module Client
    class Finish < Installation::FinishClient
      include Yast::I18n

      def initialize
        textdomain "ntp-client"
      end

      def title
        _("Writing NTP Configuration...")
      end

      def modes
        Yast::NtpClient.modified ? [:installation, :autoinst] : []
      end


      def write
        # bnc#449615, must merge the configs which Export/Import fails to do.
        # User config from installation time:
        # fortunately so far we only have the server address(es)
        pools = Yast::NtpClient.ntp_conf.pools
        log.info "pools added during installation #{pools.inspect}"

        # ntp.conf from the RPM
        Yast::NtpClient.config_has_been_read = false
        Yast::NtpClient.ProcessNtpConf

        # put users server(s) back
        Yast::NtpClient.ntp_conf.clear_pools

        pools.each_pair do |server, options|
          Yast::NtpClient.ntp_conf.add_pool(server, options)
        end

        Yast::NtpClient.write_only = true

        Yast::NtpClient.Write
      end
    end
  end
end
