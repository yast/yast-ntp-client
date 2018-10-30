require "yast"

require "cwm/widget"
require "y2ntp_client/dialog/add_pool"

Yast.import "Address"
Yast.import "NtpClient"
Yast.import "Popup"

module Y2NtpClient
  module Widgets
    # Input field with address
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
        return true if Yast::Address.Check(value)

        msg = _("Invalid pool address.")
        Yast::Popup.Error(msg)
        false
      end

      def store
        @address = value
      end
    end

    # Button that tests if server is reachable
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

    # Enable iburst option
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
        _("<b>Quick Initial Sync</b> specifies whether the 'iburst' option is used. This option " \
        "sends 4 poll requests in 2 second intervals during the initialization. It is useful for " \
        "a quick synchronization during the start of the machine.")
      end
    end

    # Enable offline option
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
        _("<b>Start Offline</b> specifies whether the 'offline' option is used. This option " \
          "skips this server during the start-up. It is useful for a machine which starts " \
          "without the network, because it speeds up the boot, and synchronizes when the machine " \
          "gets connected to the network.")
      end
    end

    class SelectFrom < CWM::MenuButton
      def initialize(address_widget)
        Yast.import "Popup"
        @address_widget = address_widget
      end

      def label
        _("Select")
      end

      def opt
        [:notify]
      end

      def items
        [[:local, _("Local Server")], [:public, _("Public Server")]]
      end

      def handle(event)
        case event["ID"]
        when :local, :public
          Dialog::AddPool.new(@address_widget, event["ID"]).run
        end

        nil
      end

      def cwm_definition
        additional = {}
        # handle_events are by default widget_id, but in radio buttons, events are
        # in fact single RadioButton
        if !handle_all_events
          event_ids = items.map(&:first)
          additional["handle_events"] = event_ids
        end

        super.merge(additional)
      end
    end

    class LocalList < CWM::Table
      def initialize
        textdomain "ntp-client"
      end

      def header
        [
          _("Syncronization server")
        ]
      end

      def items
        [
          ["2.pool.ntp.org", "2.pool.ntp.org"],
          ["3.pool.ntp.org", "3.pool.ntp.org"]
        ]
      end
    end

    class PublicList < CWM::Table
      def initialize
        textdomain "ntp-client"
      end

      def header
        [
          _("Syncronization server")
        ]
      end

      def items
        [
          ["2.pool.ntp.org", "2.pool.ntp.org"],
          ["3.pool.ntp.org", "3.pool.ntp.org"]
        ]
      end
    end

  end
end
