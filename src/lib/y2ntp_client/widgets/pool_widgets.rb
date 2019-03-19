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

      # @macro seeAbstractWidget
      def initialize(initial_value)
        textdomain "ntp-client"

        @address = initial_value
      end

      # @macro seeAbstractWidget
      def label
        # TRANSLATORS: input field label
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
        # TRANSLATORS: push button label
        _("&Test")
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
        # TRANSLATORS: checkbox label
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
        # TRANSLATORS: checkbox help for enabling quick synchronization
        _("<p><b>Quick Initial Sync</b> is useful for a quick synchronization" \
          "during the start of the machine.</p>")
      end
    end

    # Enable offline option
    class Offline < CWM::CheckBox
      # Constructor
      #
      # @param options [Hash] current ntp server address options
      def initialize(options)
        textdomain "ntp-client"
        @options = options
      end

      # @macro seeAbstractWidget
      def label
        # TRANSLATORS: check box label
        _("Start Offline")
      end

      # @macro seeAbstractWidget
      def init
        self.value = @options.key?("offline")
      end

      # @macro seeAbstractWidget
      def store
        if value
          @options["offline"] = nil
        else
          @options.delete("offline")
        end
      end

      # @macro seeAbstractWidget
      def help
        "<p>#{help_text}</p>"
      end

    private

      def help_text
        # TRANSLATORS: help text for the offline check box
        _("<b>Start Offline</b> specifies whether the 'offline' option is used. This option " \
          "skips this server during the start-up. It is useful for a machine which starts " \
          "without the network, because it speeds up the boot, and synchronizes when the machine " \
          "gets connected to the network.")
      end
    end

    # Menu Button for choosing which type of server should be added to the
    # address input field.
    class SelectFrom < CWM::MenuButton
      # Constructor
      #
      # @param address_widget [PoolAddress] the dialog pool address widget
      def initialize(address_widget)
        textdomain "ntp-client"
        @address_widget = address_widget
      end

      # @macro seeAbstractWidget
      def label
        # TRANSLATORS: menu button label
        _("&Select")
      end

      # @macro seeAbstractWidget
      def opt
        [:notify]
      end

      # @macro seeItemsSelection
      def items
        # TRANSLATORS: Menu button entries for choosing an address from a local
        #   servers list or from a public one
        [[:local, _("Local Server")], [:public, _("Public Server")]]
      end

      # @macro seeAbstractWidget
      def handle(event)
        id = event["ID"]
        Dialog::AddPool.new(@address_widget, id).run if [:local, :public].include?(id)

        nil
      end

      # @macro seeAbstractWidget
      def cwm_definition
        additional = {}
        # handle also the items id events
        if !handle_all_events
          event_ids = items.map(&:first)
          additional["handle_events"] = event_ids
        end

        super.merge(additional)
      end

      # @macro seeAbstractWidget
      def help
        # TRANSLATORS: Help for the select menu button
        _("<p><b>Select</b> permits to choose a server from the list of servers" \
          "offered by DHCP or from a public list filtered by country.</p>") \
      end
    end

    # List of NTP servers obtained from DHCP
    class LocalList < CWM::SelectionBox
      # Constructor
      #
      # @param address [String] current NTP pool address
      def initialize(address)
        textdomain "ntp-client"

        @address = address
        @servers = []
      end

      # @macro seeAbstractWidget
      def init
        read_available_servers
        self.value = @address
      end

      # @macro seeAbstractWidget
      def opt
        [:hstretch]
      end

      # @macro seeAbstractWidget
      def label
        # TRANSLATORS: selection box label
        _("Synchronization Server")
      end

      # @macro seeItemsSelection
      def items
        @servers.map { |s| [s, s] }
      end

      # @macro seeAbstractWidget
      def help
        # TRANSLATORS: help text for the local servers selection box
        _("<p>List of available NTP servers provided by DHCP. " \
          "Servers already in use are discarded.</p>")
      end

    private

      # Convenience method to read and initialize the list of available servers
      def read_available_servers
        Yast::Popup.Feedback(_("Getting NTP sources from DHCP"), Yast::Message.takes_a_while) do
          @servers = available_servers
        end
      end

      # List of available NTP servers provided by DHCP. Servers already in use
      # are discarded.
      #
      # @return [Array<String>] list of NTP servers provided by DHCP
      def available_servers
        Yast::NtpClient.dhcp_ntp_servers.reject { |s| configured_servers.include?(s) }
      end

      # List of NTP servers in use.
      #
      # @return [Array<String>] list of already configured NTP servers
      def configured_servers
        Yast::NtpClient.ntp_conf.pools.keys
      end
    end

    # List of public NTP servers filtered by country
    class PublicList < CWM::CustomWidget
      # Constructor
      #
      # @param address [String] current NTP pool address
      def initialize(address)
        textdomain "ntp-client"

        @country_pools = CountryPools.new
        @country = Country.new(country_for(address), @country_pools)
      end

      # @macro seeAbstractWidget
      def label
        # TRANSLATORS: custom widget label, the widget permits to select a
        # public server from a selection box, filtering the list by country
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
        # TRANSLATORS: help text for the public servers custom widget
        _("<p>List of public NTP servers filtered by country.</p>")
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
        # TRANSLATORS: combo box label
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
        # TRANSLATORS: Combo box entry for not filtering entries
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
        # TRANSLATORS: combo box label
        _("NTP Servers")
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
