require "yast"

require "cwm/widget"
require "cwm/table"

require "y2ntp_client/dialog/pool"

Yast.import "Confirm"
Yast.import "NtpClient"
Yast.import "Popup"

module Y2NtpClient
  module Widgets
    # Widget for netconfig policy
    class PolicyCombo < CWM::ComboBox
      def initialize
        textdomain "ntp-client"
      end

      def label
        # TRANSLATORS: label for widget that allows to define if ntp configiration is only
        # from its source or dynamically extended e.g. via DHCP
        _("Configuration Source")
      end

      def help
        # TRANSLATORS: configuration source combo box help
        _("<p>The NTP configuration may be provided by the local network over DHCP. " \
          "<b>Configuration Source</b> can simply enable or disable using that configuration. " \
          "In cases where there may be multiple DHCP sources, it can prioritize them: " \
          "see '%{manual}'.</p>") % { manual: "man 8 netconfig" }
      end

      def opt
        [:editable]
      end

      def items
        items = [
          # TRANSLATORS: combo box item
          ["", _("Static")],
          # TRANSLATORS: combo box item
          ["auto", _("Dynamic")]
        ]
        current_policy = Yast::NtpClient.ntp_policy
        if !["", "auto"].include?(current_policy)
          items << [current_policy, current_policy]
        end

        items
      end

      def init
        self.value = Yast::NtpClient.ntp_policy
      end

      def validate
        if value =~ /["']/
          # TRANSLATORS: single quote (') and double quote (") are invalid
          Yast::Popup.Error(_("Configuration Source may not contain single or double quotes"))
          Yast::UI.SetFocus(Id(widget_id))
          return false
        end

        true
      end

      def store
        return if value == Yast::NtpClient.ntp_policy

        log.info "ntp policy modifed to #{value.inspect}"
        Yast::NtpClient.modified = true
        Yast::NtpClient.ntp_policy = value
      end
    end

    # Widget to configure how ntp will be started
    class NtpStart < CWM::RadioButtons
      def initialize(replace_point)
        textdomain "ntp-client"

        @replace_point = replace_point
      end

      def label
        _("Start NTP Daemon")
      end

      def opt
        [:notify]
      end

      def items
        [
          # radio button
          ["never", _("Only &Manually")],
          # radio button
          ["sync", _("&Synchronize without Daemon")],
          # radio button
          ["boot", _("Now and on &Boot")]
        ]
      end

      def init
        self.value = if Yast::NtpClient.synchronize_time
          "sync"
        elsif Yast::NtpClient.run_service
          "boot"
        else
          "never"
        end
        handle
      end

      def handle
        widget = value == "sync" ? SyncInterval.new : CWM::Empty.new("empty_interval")
        @replace_point.replace(widget)

        nil
      end

      def help
        _(
          "<p><b><big>Start NTP Daemon</big></b><br>\n"                                        \
          "Select whether to start the NTP daemon now and on every system boot. \n"            \
          "Selecting <b>Synchronize without Daemon</b> the NTP daemon will not be activated\n" \
          "and the system time will be set periodically by a <i>cron</i> script. \n"           \
          "The interval is configurable, by default it is %d minutes.</p>"
        ) % Yast::NtpClientClass::DEFAULT_SYNC_INTERVAL
      end

      def store
        Yast::NtpClient.run_service = value == "boot"
        Yast::NtpClient.synchronize_time = value == "sync"
      end
    end

    # Widget representing how often synchronize via cron
    class SyncInterval < CWM::IntField
      def initialize
        textdomain "ntp-client"
      end

      def label
        _("Synchronization &Interval in Minutes")
      end

      def minimum
        1
      end

      def maximum
        59
      end

      def init
        self.value = Yast::NtpClient.sync_interval
      end

      def store
        Yast::NtpClient.sync_interval = value
      end
    end

    # Table with ntp pool servers
    class ServersTable < CWM::Table
      def initialize
        textdomain "ntp-client"
      end

      def opt
        [:notify]
      end

      def header
        [
          # table header for list of servers
          _("Synchronization Servers")
        ]
      end

      def handle
        address = value

        options = Yast::NtpClient.ntp_conf.pools[address]
        dialog = Dialog::Pool.new(address, options)

        res = dialog.run

        if res == :next
          Yast::NtpClient.ntp_conf.modify_pool(address, *dialog.resulting_pool)

          return :redraw
        end

        nil
      end

      def items
        Yast::NtpClient.ntp_conf.pools.keys.map do |server|
          [server, server]
        end
      end
    end

    # Button to add ntp pool server
    class AddPoolButton < CWM::PushButton
      def initialize
        textdomain "ntp-client"
      end

      def label
        _("&Add")
      end

      def handle
        dialog = Dialog::Pool.new("", Yast::NtpClient.ntp_conf.default_pool_options)

        res = dialog.run

        if res == :next
          Yast::NtpClient.ntp_conf.add_pool(*dialog.resulting_pool)

          return :redraw
        end

        nil
      end
    end

    # Button to edit ntp pool server
    class EditPoolButton < CWM::PushButton
      def initialize(table)
        textdomain "ntp-client"

        @table = table
      end

      def label
        _("&Edit")
      end

      def handle
        address = @table.value
        if !address
          Yast::Popup.Error(_("No table item is selected"))
          return nil
        end

        @table.handle
      end
    end

    # Button to delete ntp pool server
    class DeletePoolButton < CWM::PushButton
      def initialize(table)
        textdomain "ntp-client"

        @table = table
      end

      def label
        _("&Delete")
      end

      def handle
        address = @table.value
        if !address
          Yast::Popup.Error(_("No table item is selected"))
          return nil
        end

        if Yast::Confirm.Delete(address)
          Yast::NtpClient.ntp_conf.delete_pool(address)
          return :redraw
        end

        nil
      end
    end
  end
end
