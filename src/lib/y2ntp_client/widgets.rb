# note: when file start growing too much, use separated files and just require it from here

require "yast"

require "yast/cwm"
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
end
