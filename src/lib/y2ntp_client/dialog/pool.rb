require "yast"

require "cwm/dialog"
require "y2ntp_client/widgets/pool_widgets"

Yast.import "Label"
Yast.import "NtpClient"
Yast.import "Stage"

module Y2NtpClient
  module Dialog
    # Dialog to add/edit ntp pool server
    class Pool < CWM::Dialog
      # @param address [String] initial address for pool to show
      # @param options [Hash] pool options in format where
      #   key is option and value is string for key value options
      #   or nil for keyword options
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
        @address_widget = Widgets::PoolAddress.new(@address)
        VBox(
          HBox(
            @address_widget,
            HSpacing(),
            VBox(
              VSpacing(1),
              Widgets::SelectFrom.new(@address_widget)
            ),
            HSpacing(),
            VBox(
              VSpacing(1),
              Widgets::TestButton.new(@address_widget)
            )
          ),
          VSpacing(),
          HBox(
            HSpacing(),
            Widgets::Iburst.new(@options),
            HSpacing(),
            Widgets::Offline.new(@options)
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

      # Returns value set in dialog.
      # @return [Array<String, Hash>] returns pair, where first one is address and second
      #   is modified options ( see #initialize options parameter ).
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
