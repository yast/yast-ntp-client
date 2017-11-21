# note: when file start growing too much, use separated files and just require it from here

require "yast"

require "cwm/widget"
require "cwm/table"
require "tempfile"

Yast.import "LogView"
Yast.import "NtpClient"
Yast.import "Popup"
Yast.import "Progress"
Yast.import "Service"

module Y2NtpClient
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
      # TODO: not written previously, but really deserve something
    end

    def opt
      [:editable]
    end

    def items
      items = [
        # combo box item
        ["", _("Static")],
        # combo box item
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

    def store
      if value != Yast::NtpClient.ntp_policy
        log.info "ntp policy modifed to #{value.inspect}"
        Yast::NtpClient.modified = true
        Yast::NtpClient.ntp_policy = value
      end
    end
  end

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

    def store
      Yast::NtpClient.run_service = value == "boot"
      Yast::NtpClient.synchronize_time = value == "sync"
    end
  end

  class SyncInterval < CWM::IntField
    def initialize
      textdomain "ntp-client"
    end

    def label
      _("Synchronization &Interval in Minutes")
    end

    def minimal
      1
    end

    def init
      self.value = Yast::NtpClient.sync_interval
    end

    def store
      Yast::NtpClient.sync_interval = value
    end
  end

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

  class AddPoolButton < CWM::PushButton
    def initialize
      textdomain "ntp-client"
      require "y2ntp_client/dialog/pool"
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

  class EditPoolButton < CWM::PushButton
    def initialize(table)
      textdomain "ntp-client"
      require "y2ntp_client/dialog/pool"

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

      Yast::NtpClient.ntp_conf.delete_pool(address)
    end
  end
end
