require "yast"

require "cwm/widget"

Yast.import "NtpClient"

module Y2NtpClient
  module Widgets
    class PoolAddress < CWM::InputField
      attr_reader :address

      def initialize(initial_value)
        textdomain "ntp-client"
        @address = initial_value
      end

      def label
        _("A&ddress")
      end

      def init
        self.value = @address
      end

      def validate
        # TODO: validate address and also that it is not yet used
        true
      end

      def store
        @address = value
      end
    end

    class TestButton < CWM::PushButton
      def initialize(address_widget)
        textdomain "ntp-client"
        @address_widget = address_widget
      end

      def label
        _("Test")
      end

      def handle
        Yast::NtpClient.TestNtpServer(@address_widget.value, :result_popup)

        nil
      end
    end

    class Iburst < CWM::CheckBox
      def initialize(options)
        textdomain "ntp-client"
        @options = options
      end

      def label
        _("Quick Initial Sync")
      end

      def init
        self.value = @options.key?("iburst")
      end

      def store
        if value
          @options["iburst"] = nil
        else
          @options.delete("iburst")
        end
      end

      def help
        _("<b>Quick Initial Sync</b> specifies if option iburst is used. This option during " \
          "initialization send four poll requests with two seconds interval. Useful to quick " \
          "synchronization during start of machine.")
      end
    end

    class Offline < CWM::CheckBox
      def initialize(options)
        textdomain "ntp-client"
        @options = options
      end

      def label
        _("Start Offline")
      end

      def init
        self.value = @options.key?("offline")
      end

      def store
        if value
          @options["offline"] = nil
        else
          @options.delete("offline")
        end
      end

      def help
        _("<b>Start Offline</b> specifies if option offline is used. This option skip this server " \
          "during start. It is useful for machine which start without network, because it speed up " \
          " boot and sync when machine is connected to network.")
      end
    end
  end
end
