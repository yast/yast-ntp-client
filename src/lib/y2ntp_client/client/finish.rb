# encoding: utf-8

require "yast"
require "installation/finish_client"

Yast.import "NtpClient"
Yast.import "Pkg"

module Y2NtpClient
  module Client
    # Client to write ntp configuration at the end of installation
    class Finish < Installation::FinishClient
      include Yast::I18n

      REQUIRED_PACKAGE ||= "chrony"

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
        unless Pkg.PkgInstalled(REQUIRED_PACKAGE)
          Report.Error(Builtins.sformat(
            # TRANSLATORS: Popup message. %1 is the missing package name.
            _("Cannot save NTP configuration because the package %1 is not installed."),
            REQUIRED_PACKAGE))
         return false
        end

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
