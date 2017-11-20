require "yast"

require "cwm/dialog"
require "y2ntp_client/widgets"

Yast.import "Label"
Yast.import "NtpClient"
Yast.import "Stage"

module Y2NtpClient
  module Dialog
    class Main < CWM::Dialog
      # @param pool_entry [nil, Hash]
      def initialize(pool_entry = nil)
        textdomain "ntp-client"
      end

      def title
        # dialog caption
        _("Pool Configuration")
      end

      def contents
      end

      def next_button
        Yast::Label.OKButton
      end

    private

      # always open new wizard dialog
      def def should_open_dialog?
        true
      end

    end
  end
end
