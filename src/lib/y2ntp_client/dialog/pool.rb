require "yast"

require "cwm/dialog"
require "y2ntp_client/widgets"

Yast.import "Label"
Yast.import "NtpClient"
Yast.import "Stage"

module Y2NtpClient
  module Dialog
    class Pool < CWM::Dialog
      # @param pool_entry [nil, Hash]
      def initialize(address = "", options = {})
        textdomain "ntp-client"
        @address = address
        @options = options
      end

      def title
        # dialog caption
        _("Pool Configuration")
      end

      def contents
        @address_widget = PoolAddress.new(@address)
        VBox(
          HBox(
            @address_widget,
            HSpacing(),
            TestButton.new(@address_widget)
          ),
          VSpacing(),
          HBox(
            Iburst.new(@options),
            HSpacing(),
            Offline.new(@options),
          )
        )
      end

      def next_button
        Yast::Label.OKButton
      end

      def back_button
        Yast::Label.CancelButton
      end

      def abort_button
        # does not show abort, onlyce cancel/ok
        ""
      end

      def resulting_pool
        [@address_widget.address, @options]
      end

    private

      # always open new wizard dialog
      def should_open_dialog?
        true
      end
    end
  end
end
