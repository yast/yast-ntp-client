require "yast"

require "cwm/popup"

Yast.import "Label"
Yast.import "NtpClient"
Yast.import "Stage"
Yast.import "Popup"

module Y2NtpClient
  module Dialog
    # Dialog to add/edit ntp pool server
    class AddPool < ::CWM::Popup
      def initialize(address_widget, pool_type = :local)
        textdomain "ntp-client"
        @address_widget = address_widget
        @address = @address_widget.value
        @table = pool_for(pool_type)
      end

      def pool_for(type)
        { :local => Widgets::LocalList,
          :public => Widgets::PublicList }.fetch(type, Widgets::LocalList).new
      end


      def title
        _("Local ntp servers discovered")
      end

      def contents
        VBox(
          @table
        )
      end

      def next_handler
        @address = @table.value

        :next
      end

      def next_button
        ok_button_label
      end

      def run
        result = super
        @address_widget.value = @address if result == :next

        result
      end

    private

      def ok_button
        PushButton(Id(:next), Opt(:default), ok_button_label)
      end
    end
  end
end
