# note: when file start growing too much, use separated files and just require it from here

require "yast"

require "cwm/widget"
require "cwm/table"
require "tempfile"

Yast.import "LogView"
Yast.import "NtpClient"
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
    def initialize
      textdomain "ntp-client"
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
    end

    def handle
      # TODO: display interval for sync without daemon
      nil
    end

    def store
      Yast::NtpClient.run_service = value == "boot"
      Yast::NtpClient.synchronize_time = value == "sync"
    end
  end

  class ServersTable < CWM::Table
    def initialize
      textdomain "ntp-client"
    end

    def header
      [
        # table header for list of servers
        _("Synchronization Servers")
      ]
    end

    def items
      Yast::NtpClient.ntp_conf.pools.keys.map do |server|
        [server, server]
      end
    end
  end
end
