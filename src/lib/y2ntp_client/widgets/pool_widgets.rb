require "yast"

require "cwm/widget"
require "y2ntp_client/dialog/add_pool"

Yast.import "Address"
Yast.import "NtpClient"
Yast.import "Popup"
Yast.import "Lan"

module Y2NtpClient
  module Widgets
    # Input field with address
    class PoolAddress < CWM::InputField
      attr_reader :address

      # @macro seeAbstractWidget
      def initialize(initial_value)
        textdomain "ntp-client"
        @address = initial_value
      end

      # @macro seeAbstractWidget
      def label
        _("A&ddress")
      end

      # @macro seeAbstractWidget
      def init
        self.value = @address
      end

      # @macro seeAbstractWidget
      def validate
        return true if Yast::Address.Check(value)

        msg = _("Invalid pool address.")
        Yast::Popup.Error(msg)
        false
      end

      # @macro seeAbstractWidget
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
        "<p>" +
          _("<b>Quick Initial Sync</b> specifies whether the 'iburst' option is used. This " \
          "option sends 4 poll requests in 2 second intervals during the initialization. It is " \
          "useful for a quick synchronization during the start of the machine.") +
          "</p>"
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
        _("<p><b>Start Offline</b> specifies whether the 'offline' option is used. This option " \
          "skips this server during the start-up. It is useful for a machine which starts " \
          "without the network, because it speeds up the boot, and synchronizes when the machine " \
          "gets connected to the network.</p>")
      end
    end

    # Menu Button for choosing which type of server should be added to the
    # address input field.
    class SelectFrom < CWM::MenuButton
      def initialize(address_widget)
        Yast.import "Popup"
        @address_widget = address_widget
      end

      # @macro seeAbstractWidget
      def label
        _("Select")
      end

      # @macro seeAbstractWidget
      def opt
        [:notify]
      end

      # @macro seeItemsSelection
      def items
        [[:local, _("Local Server")], [:public, _("Public Server")]]
      end

      # @macro seeAbstractWidget
      def handle(event)
        case event["ID"]
        when :local, :public
          Dialog::AddPool.new(@address_widget, event["ID"]).run
        end

        nil
      end

      # @macro seeAbstractWidget
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

      def help
        _("<p><b>Select</b> permits to choose a server from the list of servers" \
          "offered by DHCP or from a public list filtered by country.</p>") \
      end
    end

    # List of ntp servers obtained from DHCP
    class LocalList < CWM::SelectionBox
      # Constructor
      #
      # @param address [String] current ntp pool address
      def initialize(address)
        textdomain "ntp-client"
        @address = address
        @servers = []
      end

      # @macro seeAbstractWidget
      def init
        Yast::Popup.Feedback(_("Getting ntp sources from DHCP"), Yast::Message.takes_a_while) do
          @servers = ntp_servers
        end
        self.value = @address
      end

      # @macro seeAbstractWidget
      def opt
        [:hstretch]
      end

      # @macro seeAbstractWidget
      def label
        _("Syncronization server")
      end

      # @macro seeItemsSelection
      def items
        @servers.map { |s| [s, s] }
      end

      # @macro seeAbstractWidget
      def help
        _("<p>List of available ntp servers provided by DHCP. " \
          "Servers already in use are discarded.</p>")
      end

    private

      # List of available ntp servers provided by DHCP. Servers already in use
      # are discarded.
      #
      # @return [Array<String>] list of ntp servers provided by dhcp
      def ntp_servers
        Yast::Lan.dhcp_ntp_servers.reject { |s| Yast::NtpClient.ntp_conf.pools.keys.include?(s) }
      end
    end

    # List of public ntp servers filtered by country
    class PublicList < CWM::CustomWidget
      # Constructor
      #
      # @param address [String] current ntp pool address
      def initialize(address)
        textdomain "ntp-client"
        @country_pools = CountryPools.new
        @country = Country.new(country_for(address), @country_pools)
      end

      # @macro seeAbstractWidget
      def label
        _("Public Servers")
      end

      # @macro seeCustomWidget
      def contents
        VBox(
          @country,
          VSpacing(),
          @country_pools
        )
      end

      # The value of this widget is the current country pool entry selected
      def value
        @country_pools.value
      end

      # @macro seeAbstractWidget
      def help
        _("<p>List of public ntp servers filtered by Country.")
      end

    private

      def country_for(address)
        Yast::NtpClient.GetNtpServers.fetch(address, {})["country"]
      end
    end

    # Country chooser
    class Country < CWM::ComboBox
      def initialize(country, country_pools)
        textdomain "ntp-client"

        @country = country
        @country_pools = country_pools
      end

      # @macro seeAbstractWidget
      def init
        self.value = @country
        refresh_country_pools
      end

      # @macro seeAbstractWidget
      def opt
        [:notify, :hstretch]
      end

      # @macro seeAbstractWidget
      def label
        _("Country")
      end

      # @macro seeItemsSelection
      def items
        country_names.map { |c, l| [c, l] }
      end

      # @macro seeAbstractWidget
      def handle
        @country = value.to_s
        refresh_country_pools
        nil
      end

    private

      def refresh_country_pools
        @country_pools.refresh(@country)
      end

      def country_names
        { "" => _("ALL") }.merge(Yast::NtpClient.GetCountryNames)
      end
    end

    # Ntp sources selector filtered by country
    class CountryPools < CWM::ComboBox
      def initialize
        textdomain "ntp-client"
      end

      # macro seeAbstractWidget
      def opt
        [:hstretch]
      end

      # macro seeAbstractWidget
      def label
        _("Ntp Servers")
      end

      # macro seeItemsSelection
      def items
        ntp_servers.map { |s, v| [s, "#{s} (#{v["country"]})"] }
      end

      def refresh(country)
        @country = country
        change_items(items)
      end

    private

      def ntp_servers
        servers = Yast::NtpClient.GetNtpServers
        return servers if @country.to_s.empty?
        servers.find_all { |_s, v| v["country"] == @country }
      end
    end
  end
end
