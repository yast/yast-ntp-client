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
end
