# note: when file start growing too much, use separated files and just require it from here

require "yast"

require "yast/cwm"
require "tempfile"

Yast.import "LogView"
Yast.import "NtpClient"
Yast.import "Progress"
Yast.import "Service"

module Y2NtpClient
  class ShowLog < CWM::PushButton
    def initialize
      textdomain "ntp-client"
    end

    def handle
      _("Display &Log...")
    end

    def handle
      # TODO: this is good for seeing log, but it is not refreshed with new log lines as it is not
      # real journalctl content. Maybe some background writting helps?
      tmp_file = Tempfile.new("yast_chronylog")
      tmp_file.close
      begin
        Yast::SCR.Execute(path(".target.bash"),
          "/usr/bin/journalctl --boot --unit chronyd --no-pager --no-tail > '#{tmp_file.path}'")
        Yast::LogView.Display(
          "file"    => tmp_file.path,
          "save"    => true,
          "actions" => [
            # menubutton entry, try to keep short
            [
              _("Restart NTP Daemon"),
              Yast.fun_ref(method(:restart_daemon), "void ()")
            ],
            # menubutton entry, try to keep short
            [
              _("Save Settings and Restart NTP Daemon"),
              Yast.fun_ref(method(:silent_write), "boolean ()")
            ]
          ]
        )
      ensure
        tmp_file.unlink
      end
      nil
    end

    def silent_write
      orig_progress = Yast::Progress.set(false)
      Yast::NtpClient.Write
      Yast::Progress.set(orig_progress)
    end

    def restart_daemon
      Yast::Service.restart(Yast::NtpClient.service_name)
    end
  end

  class CustomPolicy < CWM::InputField
    def initialize
      textdomain "ntp-client"
      @cached_value = Yast::NtpClient.ntp_policy
    end

    def label
      _("&Custom Policy")
    end

    def opt
      [:notify]
    end

    def init
      self.value = @cached_value
    end

    def handle
      @cached_value = value
    end
  end

  class PolicyCombo < CWM::ComboBox
    # @param replace_point replace point where to show custom policy input box
    def initialize(replace_point)
      textdomain "ntp-client"
      @custom_policy_widget = CustomPolicy.new
      @replace_point = replace_point
    end

    def label
      _("&Runtime Configuration Policy")
    end

    def help
      # TODO: not written previously, but really deserve something
    end

    def opt
      [:notify]
    end

    def items
      # FIXME: usability
      [
        # combo box item
        [:nomodify, _("Manual")],
        # combo box item
        [:auto, _("Auto")],
        # combo box item
        [:custom, _("Custom")]
      ]
    end

    def handle
      if value == :custom
        @replace_point.replace(@custom_policy_widget)
      else
        @replace_point.replace(CWM::Empty.new("nothing_custom"))
      end
    end

    def init
      self.value = if Yast::NtpClient.PolicyIsNomodify
        :nomodify
      elsif Yast::NtpClient.PolicyIsAuto
        :auto
      else
        :custom
      end
      handle
    end

    def store
      tmp = Yast::NtpClient.ntp_policy

      Yast::NtpClient.ntp_policy = case value
      when :nomodify then ""
      when :auto then "auto"
      when :custom then @custom_policy_widget.value
      else
        raise "unexpected value '#{value}'"
      end

      if tmp != Yast::NtpClient.ntp_policy
        log.info "set modified to true"
        Yast::NtpClient.modified = true
      end
    end
  end
end
