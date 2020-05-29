require "yast"

require "cwm/popup"

Yast.import "Label"
Yast.import "NtpClient"
Yast.import "Stage"
Yast.import "Popup"

# Work around YARD inability to link across repos/gems:

# @!macro [new] seeAbstractWidget
#   @see http://www.rubydoc.info/github/yast/yast-yast2/CWM/AbstractWidget:${0}
# @!macro [new] seeCustomWidget
#   @see http://www.rubydoc.info/github/yast/yast-yast2/CWM/CustomWidget:${0}
# @!macro [new] seeItemsSelection
#   @see http://www.rubydoc.info/github/yast/yast-yast2/CWM/ItemsSelection:${0}
# @!macro [new] seeDialog
#   @see http://www.rubydoc.info/github/yast/yast-yast2/CWM/Dialog:${0}
# @!macro [new] seePopup
#   @see http://www.rubydoc.info/github/yast/yast-yast2/CWM/Popup:${0}

module Y2NtpClient
  module Dialog
    # Dialog to add/edit ntp pool server
    class AddPool < ::CWM::Popup
      # Constructor
      #
      # @param address_widget [CWM::InputField]
      # @param pool_type [Symbol]
      def initialize(address_widget, pool_type)
        textdomain "ntp-client"

        @address_widget = address_widget
        @address = @address_widget.value
        @pool_chooser = pool_for(pool_type)
      end

      # @macro seeDialog
      def title
        # TRANSLATORS: title for choosing a ntp server dialog
        _("Available NTP servers")
      end

      # @macro seeDialog
      def contents
        VBox(
          @pool_chooser
        )
      end

      def next_handler
        return :cancel if @pool_chooser.value.to_s.empty?

        @address = @pool_chooser.value

        :next
      end

      # @macro seeDialog
      def next_button
        ok_button_label
      end

      # @macro seeDialog
      def run
        result = super
        @address_widget.value = @address if result == :next

        result
      end

    private

      # @macro seeDialog
      def ok_button
        PushButton(Id(:next), Opt(:default), ok_button_label)
      end

      def available_pools
        { local: Widgets::LocalList, public: Widgets::PublicList }
      end

      def pool_for(type)
        available_pools.fetch(type, Widgets::LocalList).new(@address_widget.value)
      end

      def min_height
        8
      end

      def buttons
        [ok_button, cancel_button]
      end
    end
  end
end
