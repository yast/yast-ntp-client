# encoding: utf-8

require "yast"
require "installation/auto_client"

Yast.import "NtpClient"
Yast.import "Progress"

require "y2ntp_client/dialog/main"

module Y2NtpClient
  module Client
    # This is a client for autoinstallation. It takes its arguments,
    # goes through the configuration and return the setting.
    # Does not do any changes to the configuration.
    class Auto < ::Installation::AutoClient
      def initialize
        textdomain "ntp-client"
      end

      def summary
        Yast::NtpClient.Summary
      end

      def import(profile)
        # as current import only modify existing configuration ( and does not contain complete
        # conf file ) we need to read original configuration and just add changes
        Yast::NtpClient.Read
        Yast::NtpClient.Import(profile)
      end

      def export
        Yast::NtpClient.Export
      end

      def reset
        Yast::NtpClient.Import({})
      end

      def change
        Y2NtpClient::Dialog::Main.run
      end

      def write
        progress_orig = Yast::Progress.set(false)
        Yast::NtpClient.write_only = true
        ret = Yast::NtpClient.Write
        Yast::Progress.set(progress_orig)

        ret
      end

      def read
        progress_orig = Yast::Progress.set(false)
        Yast::NtpClient.write_only = true
        ret = Yast::NtpClient.Read
        Yast::Progress.set(progress_orig)

        ret
      end

      def packages
        Yast::NtpClient.AutoPackages
      end

      def modified
        Yast::NtpClient.modified = true
      end

      def modified?
        Yast::NtpClient.modified
      end
    end
  end
end
